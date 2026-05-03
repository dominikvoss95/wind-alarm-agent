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