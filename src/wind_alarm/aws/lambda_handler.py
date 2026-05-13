import logging
import os
from wind_alarm.orchestrator import get_orchestrator
from wind_alarm.state import WindGraphState
from wind_alarm.config import config

# Setup logging for CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize orchestrator outside the handler for warm starts
# (This saves execution time and costs!)
orchestrator = get_orchestrator()

def handler(event, context):
    """
    AWS Lambda entry point.
    Expects event like: {"location": "kochelsee", "threshold": 12.0}
    """
    logger.info("Wind Alarm Lambda triggered with event: %s", event)

    location_id = event.get("location", os.environ.get("DEFAULT_LOCATION", "kochelsee"))
    threshold = float(event.get("threshold", os.environ.get("DEFAULT_THRESHOLD", 12.0)))
    
    location_cfg = config.LOCATIONS.get(location_id)
    if not location_cfg:
        error_msg = f"Unknown location: {location_id}"
        logger.error(error_msg)
        return {"statusCode": 400, "body": error_msg}

    results = []
    for url in location_cfg["urls"]:
        initial_state = WindGraphState(
            source_identifier=url,
            location_id=location_id,
            target_fcm_topic=location_cfg["fcm_topic"],
            threshold_knots=threshold,
            freshness_limit_minutes=int(os.environ.get("FRESHNESS_LIMIT", 60)),
        )
        
        try:
            result = orchestrator.invoke(initial_state)
            results.append({
                "url": url,
                "wind": result.get("base_wind_knots"),
                "exceeded": result.get("threshold_exceeded")
            })
        except Exception as e:
            logger.error("Error processing %s: %s", url, str(e))
            results.append({"url": url, "error": str(e)})

    return {
        "statusCode": 200,
        "body": results
    }
