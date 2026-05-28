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


from decimal import Decimal


def save_measurement(state: dict) -> bool:
    table = get_table()
    item = {
        "location_id": state.get("location_id", "default"),
        "observed_at": state.get("observed_at", datetime.now(timezone.utc).isoformat()),
        "base_wind_knots": Decimal(str(state.get("base_wind_knots", 0.0))),
        "gust_knots": Decimal(str(state.get("gust_knots", 0.0))),
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


import json
import logging

bucket_name = os.environ.get("WIND_ALARM_BUCKET")

def update_s3_measurements(location_id: str, aggregated_data: dict) -> None:
    if not bucket_name:
        logging.warning("WIND_ALARM_BUCKET environment variable is not set")
        return

    s3 = boto3.client("s3")
    key = "measurements.json"

    current_data = {}
    try:
        response = s3.get_object(Bucket=bucket_name, Key=key)
        current_data = json.loads(response["Body"].read().decode("utf-8"))
    except Exception as exc:
        logging.info("No existing measurements.json found in S3 or failed to read: %s. Creating new.", exc)

    current_data[location_id] = aggregated_data

    try:
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(current_data, indent=2),
            ContentType="application/json",
        )
        logging.info("Successfully updated %s in S3", key)
    except Exception as exc:
        logging.error("Failed to write %s to S3: %s", key, exc)


def update_s3_forecast(location_id: str, forecast_data: dict) -> None:
    if not bucket_name:
        logging.warning("WIND_ALARM_BUCKET environment variable is not set")
        return

    s3 = boto3.client("s3")
    key = "forecast.json"

    current_data = {}
    try:
        response = s3.get_object(Bucket=bucket_name, Key=key)
        current_data = json.loads(response["Body"].read().decode("utf-8"))
    except Exception as exc:
        logging.info("No existing forecast.json found in S3 or failed to read: %s. Creating new.", exc)

    current_data[location_id] = forecast_data

    try:
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(current_data, indent=2, ensure_ascii=False),
            ContentType="application/json",
        )
        logging.info("Successfully updated %s in S3", key)
    except Exception as exc:
        logging.error("Failed to write %s to S3: %s", key, exc)



def update_s3_history(location_id: str) -> None:
    if not bucket_name:
        return

    s3 = boto3.client("s3")
    key = f"history/{location_id}.json"

    try:
        items = get_recent_measurements(location_id, hours=24)
        history_list = [
            {
                "observed_at": item.get("observed_at"),
                "base_wind": float(item.get("base_wind_knots", 0.0)),
                "gust": float(item.get("gust_knots", 0.0)),
            }
            for item in items
        ]

        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(history_list, indent=2),
            ContentType="application/json",
        )
        logging.info("Successfully updated S3 history file %s", key)
    except Exception as exc:
        logging.error("Failed to write S3 history file %s: %s", key, exc)