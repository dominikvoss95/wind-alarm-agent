"""Guards from the scheduling and silent-failure audit."""

import re
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from wind_alarm.alarm_ledger import AlarmLedger
from wind_alarm.config import config
from wind_alarm.nodes import parse_primary_source
from wind_alarm.run_report import (
    FETCH_FAILED,
    MEASURED,
    OCR_UNCONFIRMED,
    STALE,
    measurement_exit_code,
    station_status,
)
from wind_alarm.schedule import (
    CEST_DAY,
    CET_DAY,
    cron_covers_local_window,
    parse_hhmm,
)
from wind_alarm.state import WindGraphState

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"


def test_workflow_if_conditions_cannot_reference_secrets():
    """GitHub rejects `secrets` inside `if:` and the workflow then never starts."""
    offenders = []
    for path in sorted(WORKFLOWS.glob("*.yml")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if re.match(r"\s*if:", line) and "secrets." in line:
                offenders.append(f"{path.name}:{number}")
    assert not offenders


def test_crons_cover_berlin_window_in_winter_and_summer():
    for location_id, spec in config.LOCATIONS.items():
        hour_expr = spec["github_cron"].split()[1]
        start = parse_hhmm(spec["local_start"])
        end = parse_hhmm(spec["local_end"])
        for day in (CET_DAY, CEST_DAY):
            missed = cron_covers_local_window(hour_expr, 15, start, end, day)
            assert missed == [], f"{location_id} {day} misses {missed}"
        bridge_hours = spec["eventbridge_cron"]
        assert spec["github_cron"].split()[1] in bridge_hours


def test_workflow_and_terraform_use_the_config_crons():
    kochel = (WORKFLOWS / "wind-alarm.yml").read_text(encoding="utf-8")
    garda = (WORKFLOWS / "gardasee-alarm.yml").read_text(encoding="utf-8")
    terraform = (ROOT / "terraform" / "main.tf").read_text(encoding="utf-8")
    assert config.LOCATIONS["kochelsee"]["github_cron"] in kochel
    assert config.LOCATIONS["gardasee"]["github_cron"] in garda
    assert config.LOCATIONS["kochelsee"]["eventbridge_cron"] in terraform
    assert config.LOCATIONS["gardasee"]["eventbridge_cron"] in terraform
    assert "cron(*/5 3-4 * * ? *)" not in terraform


def test_exit_codes_distinguish_fresh_stale_and_missing():
    assert measurement_exit_code([MEASURED, STALE]) == 0
    assert measurement_exit_code([STALE, STALE]) == 1
    assert measurement_exit_code([FETCH_FAILED]) == 2
    assert measurement_exit_code([OCR_UNCONFIRMED]) == 2
    assert measurement_exit_code([]) == 2


def test_ocr_source_is_not_a_measurement_and_garbled_text_is_not_zero():
    from wind_alarm.readings import parse_overlay_text
    reading = parse_overlay_text("S0,16-00 Oll 7026 5.9  059k3 Boe 216 kla")
    assert reading.base_wind_knots is None

    state = WindGraphState(
        fetch_status="success",
        raw_payload="/tmp/mock.png",
        fetched_at="2026-11-01T15:00:00+00:00",
        cam_timezone="Europe/Berlin",
    )
    with patch("wind_alarm.nodes._ocr_image", return_value="50, 16-00 14Pc 11.88kts"), \
         patch("wind_alarm.config.config.USE_AZURE", False), \
         patch("wind_alarm.config.config.USE_AWS", False):
        result = parse_primary_source(state)
    # A single knots token can parse, but OCR is not an alarm measurement.
    assert result.get("reading_source") == "ocr"
    assert station_status({**state, **result, "is_fresh": True}) == OCR_UNCONFIRMED
    assert measurement_exit_code([OCR_UNCONFIRMED]) == 2


def test_station_reading_status_and_duplicate_alarm(tmp_path):
    fresh = {
        "parse_status": "success",
        "reading_source": "station",
        "has_measurement_time": True,
        "is_fresh": True,
        "base_wind_knots": 12.0,
    }
    stale = dict(fresh, is_fresh=False)
    ocr = dict(fresh, reading_source="ocr")
    assert station_status(fresh) == MEASURED
    assert station_status(stale) == STALE
    assert station_status(ocr) == OCR_UNCONFIRMED

    ledger = AlarmLedger(tmp_path / "ledger.json")
    assert ledger.already_sent("kochelsee", "2026-11-01") is False
    ledger.mark_sent("kochelsee", "2026-11-01")
    assert ledger.already_sent("kochelsee", "2026-11-01") is True
    assert ledger.already_sent("gardasee", "2026-11-01") is False
    assert ledger.already_sent("kochelsee", "2026-11-02") is False


def test_http_retries_then_succeeds():
    from wind_alarm.station_client import _request
    client = MagicMock()
    failed = MagicMock(status_code=503)
    ok = MagicMock(status_code=200)
    client.get.side_effect = [failed, ok]
    with patch("wind_alarm.station_client.time.sleep") as sleep:
        response = _request(client, "https://www.addicted-sports.com/fileadmin/webcam/src/getWeatherData.php?wc=kochelsee")
    assert response is ok
    assert client.get.call_count == 2
    sleep.assert_called_once()


def test_second_trigger_same_day_does_not_send_again():
    from datetime import datetime, timezone
    from wind_alarm.aggregator import run_and_aggregate_measurements
    from wind_alarm.local.langgraph_orchestrator import LangGraphOrchestrator

    observed = datetime.now(timezone.utc).isoformat()
    fetch = {"fetch_status": "success", "raw_payload": "/tmp/s.png", "fetched_at": observed, "error_message": ""}
    parsed = {
        "parse_status": "success",
        "reading_source": "station",
        "has_measurement_time": True,
        "observed_at": observed,
        "base_wind_knots": 14.0,
        "gust_knots": 18.0,
        "error_message": "",
    }
    with patch("wind_alarm.graph.fetch_primary_source", return_value=fetch), \
         patch("wind_alarm.graph.parse_primary_source", return_value=parsed), \
         patch("wind_alarm.nodes.messaging.send", return_value="projects/test/messages/1") as send, \
         patch("wind_alarm.config.config.initialize_firebase"):
        first = run_and_aggregate_measurements("kochelsee", 10.0, 60, LangGraphOrchestrator())
        second = run_and_aggregate_measurements("kochelsee", 10.0, 60, LangGraphOrchestrator())
    assert first["notification_sent"] is True
    assert first["run_exit_code"] == 0
    assert second["notification_sent"] is False
    assert second["threshold_exceeded"] is True
    assert send.call_count == 1


def test_notifications_can_be_disabled(monkeypatch):
    monkeypatch.setenv("WIND_ALARM_SEND", "false")
    from wind_alarm.alarm_ledger import notifications_enabled
    assert notifications_enabled() is False


def test_app_exits_nonzero_without_a_measurement():
    from app import main
    import sys
    with patch("wind_alarm.orchestrator.get_orchestrator") as get_orch, \
         patch("wind_alarm.aggregator.run_and_aggregate_measurements", return_value={"webcams": {}, "threshold_exceeded": False}), \
         patch.object(sys, "argv", ["app.py", "--location", "kochelsee", "--orchestrator", "langgraph"]):
        get_orch.return_value.get_name.return_value = "LangGraph"
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code == 2
