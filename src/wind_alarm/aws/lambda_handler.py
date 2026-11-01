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

def _publish_freshness(location_id: str, fresh: bool) -> None:
    """Heartbeat metric. Missing data is what the CloudWatch alarm treats as a dead scheduler."""
    if not config.USE_AWS:
        return
    try:
        import boto3
        boto3.client("cloudwatch").put_metric_data(
            Namespace="WindAlarm",
            MetricData=[{
                "MetricName": "FreshMeasurement",
                "Dimensions": [{"Name": "Location", "Value": location_id}],
                "Value": 1.0 if fresh else 0.0,
                "Unit": "Count",
            }],
        )
    except Exception as exc:  # pylint: disable=broad-exception-caught
        logger.warning("freshness metric failed: %s", exc)


def _publish_scheduler_alive() -> None:
    if not config.USE_AWS:
        return
    try:
        import boto3
        boto3.client("cloudwatch").put_metric_data(
            Namespace="WindAlarm",
            MetricData=[{
                "MetricName": "SchedulerAlive",
                "Value": 1.0,
                "Unit": "Count",
            }],
        )
    except Exception as exc:  # pylint: disable=broad-exception-caught
        logger.warning("scheduler heartbeat failed: %s", exc)


def handler(event, context):
    """
    AWS Lambda entry point.
    Expects event like: {"location": "kochelsee", "threshold": 12.0}
    """
    logger.info("Wind Alarm Lambda triggered with event: %s", event)

    action = event.get("action", "alarm")
    if action == "heartbeat":
        _publish_scheduler_alive()
        logger.info("scheduler heartbeat published")
        return {"statusCode": 200, "body": {"heartbeat": True}}

    location_id = event.get("location", os.environ.get("DEFAULT_LOCATION", "kochelsee"))
    
    location_cfg = config.LOCATIONS.get(location_id)
    if not location_cfg:
        error_msg = f"Unknown location: {location_id}"
        logger.error(error_msg)
        return {"statusCode": 400, "body": error_msg}

    if action == "forecast":
        from wind_alarm.forecast.forecast_runner import run_forecast
        try:
            forecast_data = run_forecast(location_id)
            return {
                "statusCode": 200,
                "body": forecast_data
            }
        except Exception as e:
            logger.error("Error in forecast execution: %s", str(e))
            return {
                "statusCode": 500,
                "body": {"error": str(e)}
            }

    threshold = float(event.get("threshold", os.environ.get("DEFAULT_THRESHOLD", 12.0)))
    from wind_alarm.aggregator import run_and_aggregate_measurements

    try:
        aggregated_data = run_and_aggregate_measurements(
            location_id=location_id,
            threshold=threshold,
            freshness=int(os.environ.get("FRESHNESS_LIMIT", location_cfg.get("freshness_minutes", 60))),
            orchestrator=orchestrator,
        )
        exit_code = int(aggregated_data.get("run_exit_code", 2))
        _publish_freshness(location_id, exit_code == 0)
        # Non-zero means no fresh station reading. EventBridge then records a
        # Lambda error so the CloudWatch alarm can fire. A real 0 kt reading
        # that is fresh stays 200.
        return {
            "statusCode": 200 if exit_code == 0 else 500,
            "body": aggregated_data,
        }

    except Exception as e:
        logger.error("Error in aggregation execution: %s", str(e))
        return {
            "statusCode": 500,
            "body": {"error": str(e)}
        }
