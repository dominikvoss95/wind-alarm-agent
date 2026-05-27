import logging
import os
from wind_alarm.orchestrator import get_orchestrator
from wind_alarm.state import WindGraphState
from wind_alarm.config import config

# Setup logging for CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize orchestrator at module level to leverage Lambda warm starts
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

    from wind_alarm.aggregator import run_and_aggregate_measurements

    try:
        aggregated_data = run_and_aggregate_measurements(
            location_id=location_id,
            threshold=threshold,
            freshness=int(os.environ.get("FRESHNESS_LIMIT", 60)),
            orchestrator=orchestrator,
        )
        return {
            "statusCode": 200,
            "body": aggregated_data
        }
    except Exception as e:
        logger.error("Error in aggregation execution: %s", str(e))
        return {
            "statusCode": 500,
            "body": {"error": str(e)}
        }
