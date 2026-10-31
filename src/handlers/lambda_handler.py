"""
AWS Lambda handler for Wind Alarm.

The container image uses wind_alarm.aws.lambda_handler. This module is the
same aggregated check, so a multi-webcam location sends one notification
instead of one push per webcam.
"""
import json
from wind_alarm.config import config
from wind_alarm.orchestrator import get_orchestrator


def lambda_handler(event, context):
    location = event.get("location", "kochelsee")
    threshold = event.get("threshold", event.get("threshold_knots", 12.0))
    freshness = event.get("freshness", event.get("freshness_limit_minutes", 60))
    location_cfg = config.LOCATIONS.get(location)
    if not location_cfg:
        return {"statusCode": 400, "body": json.dumps({"error": f"Unknown: {location}"})}

    from wind_alarm.aggregator import run_and_aggregate_measurements

    try:
        aggregated = run_and_aggregate_measurements(
            location_id=location,
            threshold=float(threshold),
            freshness=int(freshness),
            orchestrator=get_orchestrator(),
        )
    except Exception as exc:  # pylint: disable=broad-exception-caught
        return {"statusCode": 500, "body": json.dumps({"error": str(exc)})}

    webcams = aggregated.get("webcams") or {}
    results = []
    for cam_id, info in webcams.items():
        if not isinstance(info, dict):
            continue
        wind = info.get("base_wind", 0.0) or 0.0
        fresh = bool(info.get("is_fresh"))
        results.append({
            "url": cam_id,
            "base_wind_knots": wind,
            "threshold_exceeded": bool(fresh and wind > float(threshold)),
        })

    return {
        "statusCode": 200,
        "body": json.dumps({
            "location": location,
            "threshold_exceeded": aggregated.get("threshold_exceeded", False),
            "notification_sent": aggregated.get("notification_sent", False),
            "results": results,
        }),
    }
