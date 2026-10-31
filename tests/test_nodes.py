"""
Tests for wind_alarm nodes.
"""
import json
from datetime import datetime, timezone, timedelta
from unittest.mock import patch, MagicMock

from wind_alarm.nodes import (
    fetch_primary_source,
    parse_primary_source,
    check_freshness,
    check_threshold,
    send_notification
)
from wind_alarm.state import WindGraphState


def test_fetch_primary_source_missing_identifier():
    """Test behavior when source_identifier is missing."""
    state = WindGraphState(source_identifier="")
    result = fetch_primary_source(state)
    assert result.get("fetch_status") == "failed"
    assert "Missing source_identifier" in result.get("error_message")


@patch("wind_alarm.nodes.capture_webcam")
def test_fetch_primary_source_success(mock_capture):
    """Station JSON and the frame path are what the parser reads."""
    mock_capture.return_value = MagicMock(
        image_path="/tmp/trimini_640.jpg",
        station_json='{"measurment":{}}',
        timezone="Europe/Berlin",
        fetched_at="2026-10-31T18:00:00+00:00",
    )
    state = WindGraphState(
        source_identifier="https://www.addicted-sports.com/webcam/kochelsee/trimini/"
    )
    result = fetch_primary_source(state)

    assert result.get("fetch_status") == "success"
    assert result.get("raw_payload") == "/tmp/trimini_640.jpg"
    assert "measurment" in result.get("station_json", "")
    assert result.get("cam_timezone") == "Europe/Berlin"
    assert result.get("error_message") == ""
    assert "fetched_at" in result


def test_parse_primary_source_skipped():
    """Test that parse skips when fetch failed."""
    state = WindGraphState(fetch_status="failed")
    result = parse_primary_source(state)
    assert result.get("parse_status") == "skipped"


@patch("easyocr.Reader")
@patch("cv2.imread")
def test_parse_primary_source_success(mock_imread, mock_reader_cls):
    """Test successful parse of valid payload."""
    mock_imread.return_value = MagicMock()

    mock_reader = MagicMock()
    mock_reader_cls.return_value = mock_reader
    mock_reader.readtext.return_value = [
        (None, "Wind 12 kts", 0.9),
        (None, "Böen 16 kts", 0.9)
    ]

    # clear the cache to ensure reader init is called
    from wind_alarm.nodes import _CACHE
    _CACHE.clear()

    state = WindGraphState(
        fetch_status="success",
        raw_payload="/tmp/mock_screenshot.png",
        fetched_at="2026-03-14T12:00:00+00:00"
    )
    result = parse_primary_source(state)
    assert result.get("parse_status") == "success"
    assert "observed_at" in result
    assert result.get("base_wind_knots") == 12.0
    assert result.get("gust_knots") == 16.0


@patch("easyocr.Reader")
@patch("cv2.imread")
def test_parse_primary_source_missing_wind_is_failure(mock_imread, mock_reader_cls):
    """OCR that does not find a wind value must not look like calm wind."""
    mock_imread.return_value = MagicMock()
    mock_reader = MagicMock()
    mock_reader_cls.return_value = mock_reader
    mock_reader.readtext.return_value = [(None, "no overlay here", 0.9)]

    from wind_alarm.nodes import _CACHE
    _CACHE.clear()

    state = WindGraphState(
        fetch_status="success",
        raw_payload="/tmp/mock_screenshot.png",
        fetched_at="2026-03-14T12:00:00+00:00",
    )
    result = parse_primary_source(state)
    assert result.get("parse_status") == "failed"
    assert "not found" in result.get("error_message", "")


@patch("cv2.imread")
def test_parse_primary_source_invalid_image(mock_imread):
    """Test parse failure on valid fetch but missing image."""
    mock_imread.return_value = None
    state = WindGraphState(fetch_status="success", raw_payload="/not/found.png")
    result = parse_primary_source(state)
    assert result.get("parse_status") == "failed"


def test_check_freshness_skipped():
    """Test freshness is skipped if parse failed."""
    state = WindGraphState(parse_status="failed")
    result = check_freshness(state)
    assert result.get("is_fresh") is False


def test_check_freshness_success():
    """Test freshness evaluation with a recent timestamp."""
    now = datetime.now(timezone.utc)
    recent = (now - timedelta(minutes=10)).isoformat()

    state = WindGraphState(
        parse_status="success",
        observed_at=recent,
        freshness_limit_minutes=30
    )
    result = check_freshness(state)
    assert result.get("is_fresh") is True


def test_check_freshness_stale():
    """Test freshness evaluation with a stale timestamp."""
    now = datetime.now(timezone.utc)
    stale = (now - timedelta(minutes=60)).isoformat()

    state = WindGraphState(
        parse_status="success",
        observed_at=stale,
        freshness_limit_minutes=30
    )
    result = check_freshness(state)
    assert result.get("is_fresh") is False


def test_check_threshold_skipped():
    """Test threshold check is skipped if not fresh."""
    state = WindGraphState(is_fresh=False)
    result = check_threshold(state)
    assert result.get("threshold_exceeded") is False


def test_check_threshold_exceeded():
    """Test threshold execution when wind exceeds limit."""
    state = WindGraphState(is_fresh=True, base_wind_knots=15.0, threshold_knots=12.0)
    result = check_threshold(state)
    assert result.get("threshold_exceeded") is True


def test_check_threshold_not_exceeded():
    """Test threshold execution when wind is below limit."""
    state = WindGraphState(is_fresh=True, base_wind_knots=10.0, threshold_knots=12.0)
    result = check_threshold(state)
    assert result.get("threshold_exceeded") is False


def test_send_notification_skipped():
    """Test notification skipped if threshold not exceeded."""
    state = WindGraphState(threshold_exceeded=False)
    result = send_notification(state)
    assert result.get("notification_sent") is False


@patch("wind_alarm.nodes.messaging.send")
def test_send_notification_skipped_when_aggregator_flag_set(mock_send):
    """Per-webcam runs must not push when the aggregator will send one alert."""
    state = WindGraphState(threshold_exceeded=True, skip_notification=True, base_wind_knots=18)
    result = send_notification(state)
    assert result.get("notification_sent") is False
    mock_send.assert_not_called()


def test_initialize_firebase_from_env_json():
    """Service account JSON from the environment must be accepted without a file."""
    payload = {"type": "service_account", "project_id": "wind-alarm-test"}
    with patch.dict("os.environ", {"FIREBASE_SERVICE_ACCOUNT_JSON": json.dumps(payload)}), \
         patch("firebase_admin.get_app", side_effect=ValueError("no app")), \
         patch("firebase_admin.credentials.Certificate") as certificate, \
         patch("firebase_admin.initialize_app") as initialize_app:
        from wind_alarm.config import config
        config.initialize_firebase()
    certificate.assert_called_once_with(payload)
    initialize_app.assert_called_once()


@patch("wind_alarm.nodes.messaging.send")
def test_send_notification_sent(mock_send):
    """Test notification sent if threshold exceeded."""
    mock_send.return_value = "mock_response"
    state = WindGraphState(threshold_exceeded=True)
    result = send_notification(state)
    assert result.get("notification_sent") is True
