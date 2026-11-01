"""
State definition for the Wind Alarm Agent.
"""
from typing_extensions import TypedDict


class WindGraphState(TypedDict, total=False):
    """
    State representing the context of a Wind Alarm execution.
    Features fields for configuration, fetch status, parsing results,
    and threshold evaluations.
    """
    source_identifier: str
    location_id: str
    target_fcm_topic: str
    threshold_knots: float
    freshness_limit_minutes: int

    raw_payload: str
    fetched_at: str
    fetch_status: str
    # Station JSON (getWeatherData.php) and the webcam timezone used to read it.
    station_json: str
    cam_timezone: str

    observed_at: str
    base_wind_knots: float
    gust_knots: float
    parse_status: str
    reading_source: str
    raw_ocr_text: str
    # False when the only timestamp is the fetch time, which is not the measurement.
    has_measurement_time: bool

    is_fresh: bool
    threshold_exceeded: bool
    notification_sent: bool
    # Set by the aggregator so each webcam run does not send its own push.
    skip_notification: bool

    error_message: str
