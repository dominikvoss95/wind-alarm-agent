"""
AWS Lambda handler for Wind Alarm.
"""
import json
from wind_alarm.config import config
from wind_alarm.state import WindGraphState
from wind_alarm.orchestrator import get_orchestrator


def lambda_handler(event, context):
    location = event.get("location", "kochelsee")
    threshold = event.get("threshold_knots", 12.0)
    location_cfg = config.LOCATIONS.get(location)
    if not location_cfg:
        return {"statusCode": 400, "body": json.dumps({"error": f"Unknown: {location}"})}

    orchestrator = get_orchestrator()
    results = []
    for url in location_cfg["urls"]:
        state = WindGraphState(source_identifier=url, location_id=location, target_fcm_topic=location_cfg["fcm_topic"], threshold_knots=threshold)
        try:
            result = orchestrator.invoke(state)
            results.append({"url": url, "base_wind_knots": result.get("base_wind_knots"), "threshold_exceeded": result.get("threshold_exceeded")})
        except Exception as e:
            results.append({"url": url, "error": str(e)})

    return {"statusCode": 200, "body": json.dumps({"location": location, "results": results})}