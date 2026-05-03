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

    observed_at: str
    base_wind_knots: float
    gust_knots: float
    parse_status: str

    is_fresh: bool
    threshold_exceeded: bool
    notification_sent: bool
    firestore_saved: bool

    error_message: str
