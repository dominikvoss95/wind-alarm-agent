"""Push payload, aggregation, and the stored reading the app displays."""

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

from wind_alarm.aggregator import run_and_aggregate_measurements
from wind_alarm.config import config
from wind_alarm.local.langgraph_orchestrator import LangGraphOrchestrator
from wind_alarm.notify import ALARM_SOUND, build_alarm_message
from wind_alarm import store


def _apns_fields(message):
    aps = message.apns.payload.aps
    return {
        "priority": message.apns.headers["apns-priority"],
        "push_type": message.apns.headers["apns-push-type"],
        "sound": aps.sound,
        "content_available": aps.content_available,
        "interruption": (aps.custom_data or {}).get("interruption-level"),
        "action": message.data["action"],
        "location": message.data["location"],
        "wind": message.data["wind"],
        "topic": message.topic,
    }


def test_alarm_message_has_apns_fields_for_each_location():
    cases = [
        ("kochelsee", "wind_alarms_kochelsee", 11.5),
        ("gardasee", "wind_alarms_gardasee", 14),
    ]
    for location_id, topic, wind in cases:
        message = build_alarm_message(
            topic=topic,
            title="t",
            body="b",
            location_id=location_id,
            wind_knots=wind,
        )
        fields = _apns_fields(message)
        assert fields["topic"] == topic
        assert fields["priority"] == "10"
        assert fields["push_type"] == "alert"
        assert fields["sound"] == ALARM_SOUND
        assert fields["content_available"] is True
        assert fields["interruption"] == "time-sensitive"
        assert fields["action"] == "schedule_alarm"
        assert fields["location"] == location_id
        assert message.android.priority == "high"
        assert message.notification is not None
    assert build_alarm_message(
        topic="wind_alarms_kochelsee", title="t", body="b", location_id="kochelsee", wind_knots=10
    ).data["wind"] == "10"
    assert build_alarm_message(
        topic="wind_alarms_gardasee", title="t", body="b", location_id="gardasee", wind_knots=12.5
    ).data["wind"] == "12.5"


def test_ios_firebase_project_and_bundle_match_the_app():
    plist = Path("app/ios/Runner/GoogleService-Info.plist").read_text(encoding="utf-8")
    options = Path("app/lib/firebase_options.dart").read_text(encoding="utf-8")
    ios = options.split("static const FirebaseOptions ios")[1].split("static const FirebaseOptions")[0]
    assert "<string>de.dominikvoss.wind-alarm</string>" in plist
    assert "wind-alarm-agent" in plist
    assert "wind-alarm-agent-eb65f" not in plist
    assert "de.dominikvoss.wind-alarm" in ios
    assert "projectId: 'wind-alarm-agent'" in ios
    assert "messagingSenderId: '361158488010'" in ios
    assert "wind-alarm-agent-eb65f" not in ios
    assert "com.example.app" not in ios
    assert "com.dominikvoss.windalarm" not in plist

    release = Path("app/ios/Runner/Release.entitlements").read_text(encoding="utf-8")
    debug = Path("app/ios/Runner/Debug.entitlements").read_text(encoding="utf-8")
    info = Path("app/ios/Runner/Info.plist").read_text(encoding="utf-8")
    project = Path("app/ios/Runner.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    assert "<string>production</string>" in release
    assert "aps-environment" in release
    assert "<string>development</string>" in debug
    assert "remote-notification" in info
    assert "CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements" in project
    assert "CODE_SIGN_ENTITLEMENTS = Runner/Debug.entitlements" in project
    assert config.EXPECTED_FIREBASE_PROJECT_ID == "wind-alarm-agent"
    assert config.IOS_BUNDLE_ID == "de.dominikvoss.wind-alarm"


def test_service_account_project_mismatch_is_logged_without_the_key():
    payload = {"type": "service_account", "project_id": "wind-alarm-agent-eb65f", "private_key": "secret-value"}
    with patch.dict("os.environ", {"FIREBASE_SERVICE_ACCOUNT_JSON": json.dumps(payload)}), \
         patch("firebase_admin.get_app", side_effect=ValueError("no app")), \
         patch("firebase_admin.credentials.Certificate") as certificate, \
         patch("firebase_admin.initialize_app"), \
         patch("logging.error") as log_error:
        config.initialize_firebase()
    certificate.assert_called_once()
    logged = " ".join(str(call) for call in log_error.call_args_list)
    assert "wind-alarm-agent-eb65f" in logged
    assert "secret-value" not in logged


def _graph_result(observed, wind, gust=1.0):
    return (
        {
            "fetch_status": "success",
            "raw_payload": "/tmp/shot.png",
            "fetched_at": observed,
            "error_message": "",
        },
        {
            "parse_status": "success",
            "observed_at": observed,
            "base_wind_knots": wind,
            "gust_knots": gust,
            "has_measurement_time": True,
            "error_message": "",
        },
    )


def _run(location, threshold, winds):
    """winds is a list of (wind, minutes_old) in webcam URL order."""
    now = datetime.now(timezone.utc)
    fetches = []
    parses = []
    for wind, minutes in winds:
        observed = (now - timedelta(minutes=minutes)).isoformat()
        fetch, parse = _graph_result(observed, wind, gust=wind + 2)
        fetches.append(fetch)
        parses.append(parse)

    with patch("wind_alarm.graph.fetch_primary_source", side_effect=fetches), \
         patch("wind_alarm.graph.parse_primary_source", side_effect=parses), \
         patch("wind_alarm.nodes.messaging.send", return_value="projects/test/messages/1") as send, \
         patch("wind_alarm.config.config.initialize_firebase"):
        result = run_and_aggregate_measurements(
            location_id=location,
            threshold=threshold,
            freshness=60,
            orchestrator=LangGraphOrchestrator(),
        )
    return result, send


def test_kochelsee_alarm_matches_the_reading_and_sends_one_push():
    result, send = _run("kochelsee", 10.0, [(10.0, 5)])
    assert result["threshold_exceeded"] is False
    assert result["notification_sent"] is False
    assert send.call_count == 0
    stored = store.get_measurement("kochelsee")
    assert stored["base_wind"] == 10.0
    assert stored["threshold_exceeded"] is False

    result, send = _run("kochelsee", 10.0, [(10.4, 5)])
    assert result["threshold_exceeded"] is True
    assert result["notification_sent"] is True
    assert send.call_count == 1
    message = send.call_args[0][0]
    fields = _apns_fields(message)
    assert fields["topic"] == "wind_alarms_kochelsee"
    assert fields["wind"] == "10.4"
    assert fields["sound"] == ALARM_SOUND
    stored = store.get_measurement("kochelsee")
    assert stored["base_wind"] == 10.4
    assert stored["is_fresh"] is True
    assert stored["threshold_exceeded"] is True


def test_stale_reading_does_not_alarm_even_above_the_threshold():
    result, send = _run("kochelsee", 10.0, [(18.0, 90)])
    assert result["is_fresh"] is False
    assert result["threshold_exceeded"] is False
    assert result["notification_sent"] is False
    assert send.call_count == 0
    stored = store.get_measurement("kochelsee")
    assert stored["base_wind"] == 18.0
    assert stored["is_fresh"] is False
    assert stored["threshold_exceeded"] is False


def test_gardasee_sends_one_push_only_for_a_trigger_spot():
    # Malcesine Nord calm, Malcesine over 12, Campione much higher but not a trigger.
    result, send = _run("gardasee", 12.0, [(3.0, 4), (13.2, 4), (30.0, 4)])
    assert result["threshold_exceeded"] is True
    assert send.call_count == 1
    message = send.call_args[0][0]
    fields = _apns_fields(message)
    assert fields["topic"] == "wind_alarms_gardasee"
    assert fields["location"] == "gardasee"
    assert fields["wind"] == "13.2"
    assert "30" not in message.notification.body
    assert "Malcesine" in message.notification.body
    stored = store.get_measurement("gardasee")
    assert stored["webcams"]["malcesine"]["base_wind"] == 13.2
    assert stored["webcams"]["campione"]["base_wind"] == 30.0
    assert stored["threshold_exceeded"] is True

    # Only Campione is over the threshold. That must not push.
    result, send = _run("gardasee", 12.0, [(4.0, 4), (11.0, 4), (20.0, 4)])
    assert result["threshold_exceeded"] is False
    assert result["notification_sent"] is False
    assert send.call_count == 0

    # Malcesine is over the threshold but the sample is older than 60 minutes.
    result, send = _run("gardasee", 12.0, [(4.0, 4), (16.0, 120), (4.0, 4)])
    assert result["threshold_exceeded"] is False
    assert send.call_count == 0
