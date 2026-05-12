"""
DynamoDB-based Knowledge Base for historical wind data.
"""
import os
import boto3
from datetime import datetime, timezone
from typing import List, Optional


dynamodb = None
table_name = os.environ.get("WIND_ALARM_KB_TABLE", "wind-alarm-knowledge-base")


def get_table():
    global dynamodb
    if dynamodb is None:
        dynamodb = boto3.resource("dynamodb", region_name="eu-central-1")
    return dynamodb.Table(table_name)


def save_measurement(state: dict) -> bool:
    table = get_table()
    item = {
        "location_id": state.get("location_id", "default"),
        "observed_at": state.get("observed_at", datetime.now(timezone.utc).isoformat()),
        "base_wind_knots": state.get("base_wind_knots", 0.0),
        "gust_knots": state.get("gust_knots", 0.0),
        "threshold_exceeded": state.get("threshold_exceeded", False),
        "ttl": int(datetime.now(timezone.utc).timestamp()) + (90 * 24 * 60 * 60),
    }
    table.put_item(Item=item)
    return True


def get_recent_measurements(location_id: str, hours: int = 24) -> List[dict]:
    table = get_table()
    since = datetime.now(timezone.utc).timestamp() - (hours * 3600)
    response = table.query(
        KeyConditionExpression="location_id = :loc AND observed_at >= :since",
        ExpressionAttributeValues={":loc": location_id, ":since": datetime.fromtimestamp(since, tz=timezone.utc).isoformat()},
        ScanIndexForward=False, Limit=100,
    )
    return response.get("Items", [])


def get_average_wind(location_id: str, hours: int = 24) -> Optional[float]:
    measurements = get_recent_measurements(location_id, hours)
    winds = [m["base_wind_knots"] for m in measurements if m["base_wind_knots"] > 0]
    return sum(winds) / len(winds) if winds else None