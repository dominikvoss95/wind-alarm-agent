"""Parsing, freshness, and fixture truth for webcam wind readings."""

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from wind_alarm.config import config
from wind_alarm.nodes import check_freshness, check_threshold
from wind_alarm.readings import (
    agrees_with_any_sample,
    crop_overlay,
    observed_from_page_url,
    parse_overlay_text,
    parse_station_payload,
    parse_vision_payload,
    station_samples,
)
from wind_alarm.state import WindGraphState

FIXTURES = Path(__file__).parent / "fixtures"
EXPECTED = json.loads((FIXTURES / "expected.json").read_text(encoding="utf-8"))


def _station_payload():
    """Two real minutes from Kochelsee on 2026-10-31. Newest is 19:00 local."""
    return {
        "measurment": {
            "172 2026-10-31 19:00:00": {
                "temp": "7.6",
                "wsavg": "0",
                "wsmax": "1.62",
                "tsdatetime": "2026-10-31 19:00:00",
                "utctstamp": "1793469600",
            },
            "172 2026-10-31 18:59:00": {
                "temp": "7.6",
                "wsavg": "1.08",
                "wsmax": "3.24",
                "tsdatetime": "2026-10-31 18:59:00",
                "utctstamp": "1793469540",
            },
        }
    }


def test_fixture_images_exist_and_overlay_text_matches_known_truth():
    for name, spec in EXPECTED.items():
        image = FIXTURES / name
        assert image.is_file()
        assert image.stat().st_size > 1000
        reading = parse_overlay_text(spec["overlay_text"], spec["timezone"])
        assert not reading.warnings
        assert reading.base_wind_knots == spec["base_wind_knots"]
        assert reading.gust_knots == spec["gust_knots"]
        assert reading.temperature_c == spec["temperature_c"]
        assert reading.observed_at == datetime.fromisoformat(spec["observed_at_utc"])
        # The hour and the °C value must not become the wind.
        assert reading.base_wind_knots != 19
        assert reading.base_wind_knots != reading.temperature_c


def test_overlay_accepts_panel_labels_decimals_and_comma():
    panel = parse_overlay_text("Luft: 8 °C\nWind: 12.5 kts\nBöen: 18 kts")
    assert panel.base_wind_knots == 12.5
    assert panel.gust_knots == 18

    comma = parse_overlay_text("SA, 19:00\n31.10.2026\n8°C\n4 kts\nBoe 7,56 kts")
    assert comma.base_wind_knots == 4
    assert comma.gust_knots == 7.56


def test_overlay_rejects_temperature_clock_other_units_and_ambiguous_knots():
    temp = parse_overlay_text("19:00\n31.10.2026\n16°C\n16 kts\nBöe 7.56 kts")
    assert temp.base_wind_knots is None
    assert any("temperature" in note for note in temp.warnings)

    clock = parse_overlay_text("19:00\n31.10.2026\n8°C\n19 kts\nBöe 4 kts")
    assert clock.base_wind_knots is None
    assert any("clock" in note for note in clock.warnings)

    other = parse_overlay_text("Wind 30 km/h")
    assert other.base_wind_knots is None
    assert any("km/h" in note for note in other.warnings)

    ambiguous = parse_overlay_text("22 kts 4 kts Böe 7.56 kts")
    assert ambiguous.base_wind_knots is None
    assert any("ambiguous" in note for note in ambiguous.warnings)

    missing = parse_overlay_text("no overlay here")
    assert missing.base_wind_knots is None
    assert any("not found" in note for note in missing.warnings)

    gust_only = parse_overlay_text("Böe 14 kts")
    assert gust_only.base_wind_knots is None


def test_parse_prefers_station_json_over_ocr():
    from wind_alarm.nodes import parse_primary_source
    state = WindGraphState(
        fetch_status="success",
        station_json=json.dumps(_station_payload()),
        raw_payload="/tmp/should-not-be-read.png",
        cam_timezone="Europe/Berlin",
        fetched_at="2026-10-31T18:05:00+00:00",
    )
    result = parse_primary_source(state)
    assert result["parse_status"] == "success"
    assert result["reading_source"] == "station"
    assert result["base_wind_knots"] == 0.0
    assert result["gust_knots"] == 1.62
    assert result["has_measurement_time"] is True
    assert result["observed_at"].startswith("2026-10-31T18:00:00")


def test_station_payload_uses_newest_sample_and_utc_stamp():
    reading = parse_station_payload(_station_payload(), "Europe/Berlin")
    assert reading.base_wind_knots == 0.0
    assert reading.gust_knots == 1.62
    assert reading.observed_at == datetime(2026, 10, 31, 18, 0, tzinfo=timezone.utc)
    samples = station_samples(_station_payload())
    overlay = parse_overlay_text(EXPECTED["kochelsee_trimini_640.jpg"]["overlay_text"])
    agree, detail = agrees_with_any_sample(samples, overlay)
    assert agree, detail
    # The newest minute alone is 0 kt; the burned-in frame still shows 1.08.
    assert abs(reading.base_wind_knots - overlay.base_wind_knots) > 0.5


def test_vision_payload_rejects_temperature_and_the_clock():
    good = parse_vision_payload(
        {"wind": 4, "gust": 7.56, "temperature_c": 16, "local_time": "2026-10-31T19:00"},
        "Europe/Rome",
    )
    assert good.base_wind_knots == 4
    assert good.gust_knots == 7.56
    assert good.observed_at == datetime(2026, 10, 31, 18, 0, tzinfo=timezone.utc)

    as_temp = parse_vision_payload({"wind": 16, "gust": 7.56, "temperature_c": 16})
    assert as_temp.base_wind_knots is None

    as_clock = parse_vision_payload(
        {"wind": 19, "gust": 5, "temperature_c": 16, "local_time": "2026-10-31T19:00"}
    )
    assert as_clock.base_wind_knots is None

    missing = parse_vision_payload({"gust": 5})
    assert missing.base_wind_knots is None
    assert any("not found" in note for note in missing.warnings)


def test_malcesine_station_id_is_not_the_url_slug():
    spec = config.webcam_for_url("https://www.addicted-sports.com/webcam/gardasee/malcesine/")
    assert spec["wc"] == "gardasee"
    assert spec["slug"] == "malcesine"
    assert spec["image_url"].endswith("/gardasee/current/640.jpg")


def test_verify_exit_code_requires_every_webcam_to_agree():
    from wind_alarm.verify import exit_code
    assert exit_code([{"agree": True}, {"agree": True}]) == 0
    assert exit_code([{"agree": False}]) == 1
    assert exit_code([]) == 1


def test_archive_hash_is_local_time_not_utc():
    url = "https://www.addicted-sports.com/webcam/kochelsee/trimini/#/2026/10/31/1900"
    observed = observed_from_page_url(url, "Europe/Berlin")
    assert observed == datetime(2026, 10, 31, 18, 0, tzinfo=timezone.utc)


def test_crop_keeps_the_bottom_left_overlay():
    class _Image:
        def __init__(self):
            self.shape = (100, 200, 3)
            self.key = None

        def __getitem__(self, key):
            self.key = key
            return "cropped"

    image = _Image()
    assert crop_overlay(image) == "cropped"
    rows, cols = image.key
    assert rows.start == 60
    assert rows.stop == 100
    assert cols.start == 0
    assert cols.stop == 76


def test_freshness_uses_measurement_time_and_sixty_minute_limit():
    now = datetime.now(timezone.utc)
    fresh = check_freshness(WindGraphState(
        parse_status="success",
        observed_at=(now - timedelta(minutes=10)).isoformat(),
        freshness_limit_minutes=60,
        has_measurement_time=True,
    ))
    assert fresh["is_fresh"] is True

    exactly = check_freshness(WindGraphState(
        parse_status="success",
        observed_at=(now - timedelta(minutes=60) + timedelta(seconds=2)).isoformat(),
        freshness_limit_minutes=60,
        has_measurement_time=True,
    ))
    assert exactly["is_fresh"] is True

    stale = check_freshness(WindGraphState(
        parse_status="success",
        observed_at=(now - timedelta(minutes=61)).isoformat(),
        freshness_limit_minutes=60,
        has_measurement_time=True,
    ))
    assert stale["is_fresh"] is False

    future = check_freshness(WindGraphState(
        parse_status="success",
        observed_at=(now + timedelta(minutes=90)).isoformat(),
        freshness_limit_minutes=60,
        has_measurement_time=True,
    ))
    assert future["is_fresh"] is False

    skew = check_freshness(WindGraphState(
        parse_status="success",
        observed_at=(now + timedelta(minutes=1)).isoformat(),
        freshness_limit_minutes=60,
        has_measurement_time=True,
    ))
    assert skew["is_fresh"] is True

    fetch_only = check_freshness(WindGraphState(
        parse_status="success",
        observed_at=now.isoformat(),
        has_measurement_time=False,
        freshness_limit_minutes=60,
    ))
    assert fetch_only["is_fresh"] is False


def test_thresholds_are_strict_and_per_location():
    assert check_threshold(WindGraphState(
        is_fresh=True, base_wind_knots=10.0, threshold_knots=10.0
    ))["threshold_exceeded"] is False
    assert check_threshold(WindGraphState(
        is_fresh=True, base_wind_knots=10.1, threshold_knots=10.0
    ))["threshold_exceeded"] is True
    assert check_threshold(WindGraphState(
        is_fresh=True, base_wind_knots=12.0, threshold_knots=12.0
    ))["threshold_exceeded"] is False
    assert check_threshold(WindGraphState(
        is_fresh=True, base_wind_knots=12.4, threshold_knots=12.0
    ))["threshold_exceeded"] is True
    assert check_threshold(WindGraphState(
        is_fresh=False, base_wind_knots=30.0, threshold_knots=10.0
    ))["threshold_exceeded"] is False


@pytest.mark.live
def test_live_station_reading_is_plausible():
    """Manual check against the real Trimini station. Not part of CI."""
    from wind_alarm.station_client import capture_webcam

    captured = capture_webcam("https://www.addicted-sports.com/webcam/kochelsee/trimini/")
    reading = parse_station_payload(json.loads(captured.station_json), captured.timezone)
    assert reading.base_wind_knots is not None
    assert 0 <= reading.base_wind_knots <= 75
    age = datetime.now(timezone.utc) - reading.observed_at
    assert abs(age.total_seconds()) < 3 * 3600
