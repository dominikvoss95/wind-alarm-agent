"""
Aggregated checking and notification module for multiple webcams per location.
"""
import logging
from typing import Dict, Any, List
from firebase_admin import messaging

from wind_alarm.config import config
from wind_alarm.state import WindGraphState
from wind_alarm import store

TRIGGER_SPOTS = {
    "gardasee": ["malcesinenord", "malcesine"],
    "kochelsee": ["trimini"],
}

WEBCAM_NAMES = {
    "malcesinenord": "Malcesine Nord",
    "malcesine": "Malcesine",
    "campione": "Campione",
    "trimini": "Kochelsee (Trimini)",
}


def clean_cam_id(url: str) -> str:
    """Extract clean webcam ID from the URL path."""
    return url.rstrip("/").split("/")[-1].lower()


def _extract_cam_data(res: Any) -> Dict[str, Any]:
    """Helper to extract webcam details safely, handling mocks."""
    if hasattr(res, "get"):
        return {
            "base_wind": res.get("base_wind_knots", 0.0),
            "gust": res.get("gust_knots", 0.0),
            "is_fresh": res.get("is_fresh", False),
            "observed_at": res.get("observed_at"),
        }
    return {
        "base_wind": 0.0,
        "gust": 0.0,
        "is_fresh": False,
        "observed_at": None,
    }


def _get_max_wind(results: Dict[str, Any]) -> float:
    """Extract max wind speed safely, handling potential MagicMocks in testing."""
    wind_values = []
    for res in results.values():
        if hasattr(res, "get"):
            val = res.get("base_wind_knots", 0.0)
            if isinstance(val, (int, float)):
                wind_values.append(val)
            else:
                try:
                    wind_values.append(float(val))
                except (ValueError, TypeError):
                    wind_values.append(0.0)
        else:
            wind_values.append(0.0)
    return max(wind_values) if wind_values else 0.0


def _build_notification_body(
    trigger_spots: List[str],
    results: Dict[str, Any]
) -> str:
    """Build concise lock-screen message details."""
    spots_with_wind = []
    for spot in trigger_spots:
        if spot in results and results[spot].get("threshold_exceeded"):
            name = WEBCAM_NAMES.get(spot, spot)
            wind = results[spot]["base_wind_knots"]
            spots_with_wind.append(f"{name}: {wind} kts")
    return "Wind: " + ", ".join(spots_with_wind)


def _evaluate_trigger(location_id: str, results: Dict[str, Any]) -> bool:
    """Evaluate alarm condition based on defined key spots."""
    trigger_spots = TRIGGER_SPOTS.get(location_id, [])
    for spot in trigger_spots:
        if spot in results:
            res = results[spot]
            if res.get("threshold_exceeded") and res.get("is_fresh"):
                return True
    return False


def _send_notification_if_triggered(
    location_id: str,
    location_cfg: Dict[str, Any],
    results: Dict[str, Any],
    should_trigger: bool
) -> bool:
    """Send FCM notification if should_trigger is True."""
    if not should_trigger:
        return False

    trigger_spots = TRIGGER_SPOTS.get(location_id, [])
    body = _build_notification_body(trigger_spots, results)
    topic = location_cfg["fcm_topic"]
    max_wind = _get_max_wind(results)

    message = messaging.Message(
        notification=messaging.Notification(
            title=f"💨 Wind-Alarm: {location_cfg['name']}!",
            body=body,
        ),
        data={
            "action": "schedule_alarm",
            "location": location_id,
            "wind": str(max_wind),
        },
        topic=topic,
    )

    try:
        config.initialize_firebase()
        response = messaging.send(message)
        logging.info("Successfully sent consolidated notification: %s", response)
        return True
    except Exception as exc:  # pylint: disable=broad-exception-caught
        logging.error("Failed to send consolidated notification: %s", exc)
        return False


def _build_aggregated_dict(
    best_res: Any,
    should_trigger: bool,
    notification_sent: bool,
    results: Dict[str, Any]
) -> Dict[str, Any]:
    """Construct final aggregated payload for storing and returning."""
    has_get = hasattr(best_res, "get")
    has_success = any(
        hasattr(r, "get") and r.get("parse_status") == "success"
        for r in results.values()
    )
    any_fresh = any(
        hasattr(r, "get") and r.get("is_fresh")
        for r in results.values()
    )
    return {
        "base_wind_knots": (
            best_res.get("base_wind_knots", 0.0) if has_get else 0.0
        ),
        "gust_knots": (
            best_res.get("gust_knots", 0.0) if has_get else 0.0
        ),
        "observed_at": (
            best_res.get("observed_at") if has_get else None
        ),
        "fetched_at": (
            best_res.get("fetched_at") if has_get else None
        ),
        "parse_status": "success" if has_success else "failed",
        "is_fresh": any_fresh,
        "threshold_exceeded": should_trigger,
        "notification_sent": notification_sent,
        "error_message": (
            best_res.get("error_message", "") if has_get else ""
        ),
        "webcams": {
            cam_id: _extract_cam_data(r)
            for cam_id, r in results.items()
        }
    }


def _fetch_all_webcams(
    location_id: str,
    location_cfg: Dict[str, Any],
    threshold: float,
    freshness: int,
    orchestrator
) -> Dict[str, Any]:
    """Fetch results for all webcams of a location."""
    results = {}
    for url in location_cfg["urls"]:
        cam_id = clean_cam_id(url)
        initial_state = WindGraphState(
            source_identifier=url,
            location_id=location_id,
            target_fcm_topic=location_cfg["fcm_topic"],
            threshold_knots=threshold,
            freshness_limit_minutes=freshness,
            skip_notification=True,
        )

        try:
            results[cam_id] = orchestrator.invoke(initial_state)
        except Exception as exc:  # pylint: disable=broad-exception-caught
            logging.error("Error invoking graph for %s: %s", url, exc)
            results[cam_id] = {
                "base_wind_knots": 0.0,
                "gust_knots": 0.0,
                "parse_status": "failed",
                "is_fresh": False,
                "threshold_exceeded": False,
                "error_message": str(exc),
            }
    return results


def _log_summary(
    location_id: str,
    should_trigger: bool,
    results: Dict[str, Any]
) -> None:
    """Build and write human-readable status overview to the log."""
    summary_parts = []
    for cam_id, res in results.items():
        name = WEBCAM_NAMES.get(cam_id, cam_id.capitalize())
        wind = res.get("base_wind_knots", 0.0) if hasattr(res, "get") else 0.0
        status = (
            "fresh" if hasattr(res, "get") and res.get("is_fresh")
            else "stale/error"
        )
        summary_parts.append(f"{name}: {wind} kts ({status})")

    logging.info(
        "Aggregation Results for %s: should_trigger=%s. Details: %s",
        location_id, should_trigger, ", ".join(summary_parts)
    )


def _find_best_res(results: Dict[str, Any]) -> Any:
    """Resolve 'best' (primary) dataset for backward compatibility."""
    best_res = list(results.values())[0] if results else {}
    for res in results.values():
        if hasattr(res, "get") and res.get("threshold_exceeded"):
            return res
    return best_res


def run_and_aggregate_measurements(
    location_id: str,
    threshold: float,
    freshness: int,
    orchestrator
) -> Dict[str, Any]:
    """
    Execute data fetching for all webcams of a location, aggregate findings,
    evaluate alarm criteria, send notifications and persist results.
    """
    location_cfg = config.LOCATIONS.get(location_id)
    if not location_cfg:
        raise ValueError(f"Unknown location: {location_id}")

    results = _fetch_all_webcams(
        location_id=location_id,
        location_cfg=location_cfg,
        threshold=threshold,
        freshness=freshness,
        orchestrator=orchestrator
    )

    should_trigger = _evaluate_trigger(location_id, results)
    _log_summary(location_id, should_trigger, results)

    notification_sent = _send_notification_if_triggered(
        location_id=location_id,
        location_cfg=location_cfg,
        results=results,
        should_trigger=should_trigger,
    )

    best_res = _find_best_res(results)
    aggregated_data = _build_aggregated_dict(
        best_res=best_res,
        should_trigger=should_trigger,
        notification_sent=notification_sent,
        results=results,
    )

    store.set_measurement(location_id, aggregated_data)

    if config.USE_AWS:
        try:
            from aws.knowledge_base import save_measurement, update_s3_measurements, update_s3_history
            db_state = dict(aggregated_data)
            db_state["location_id"] = location_id
            save_measurement(db_state)
            logging.info("Successfully persisted measurement to DynamoDB history for %s", location_id)
            
            # Write static files to S3
            update_s3_measurements(location_id, aggregated_data)
            update_s3_history(location_id)
        except Exception as exc:
            logging.warning("Failed to persist measurement to DynamoDB/S3: %s", exc)

    return aggregated_data
