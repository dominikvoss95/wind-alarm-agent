"""
In-memory store for wind measurements.
"""
from typing import Optional
from datetime import datetime, timezone
from threading import Lock

_measurements: dict[str, dict] = {}
_lock = Lock()


def get_measurement(location: str) -> Optional[dict]:
    """Get latest measurement for a location."""
    with _lock:
        return _measurements.get(location)


def to_public_measurement(data: dict) -> dict:
    """Add the field names the API and the Flutter app both read.

    Aggregated runs store ``base_wind_knots`` and ``parse_status``. The mobile
    client treats a reading as fresh only when ``updated_at`` is present and
    reads ``base_wind`` / ``fetch_status``.
    """
    payload = dict(data)
    payload.setdefault("base_wind", payload.get("base_wind_knots", 0.0))
    payload.setdefault("gust", payload.get("gust_knots", 0.0))
    if not payload.get("fetch_status"):
        payload["fetch_status"] = payload.get("parse_status") or "unknown"
    if not payload.get("updated_at"):
        payload["updated_at"] = datetime.now(timezone.utc).isoformat()
    if payload.get("error_message") is None:
        payload["error_message"] = ""
    return payload


def set_measurement(location: str, data: dict) -> None:
    """Store measurement for a location."""
    with _lock:
        _measurements[location] = {
            "base_wind": data.get("base_wind_knots", 0.0),
            "gust": data.get("gust_knots", 0.0),
            "observed_at": data.get("observed_at"),
            "fetched_at": data.get("fetched_at"),
            "fetch_status": data.get("parse_status", "unknown"),
            "is_fresh": data.get("is_fresh", False),
            "threshold_exceeded": data.get("threshold_exceeded", False),
            "error_message": data.get("error_message", ""),
            "webcams": data.get("webcams", {}),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }


def get_all_measurements() -> dict[str, dict]:
    """Get all measurements."""
    with _lock:
        return dict(_measurements)


def clear_measurement(location: str) -> None:
    """Clear measurement for a location."""
    with _lock:
        _measurements.pop(location, None)