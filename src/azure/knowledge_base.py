"""
Cosmos DB and Azure Blob Storage Knowledge Base for historical wind data.
"""
import os
import json
import logging
from datetime import datetime, timezone
from typing import List, Optional, Any
from decimal import Decimal

from azure.cosmos import CosmosClient, PartitionKey
from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential

from wind_alarm.config import config

logger = logging.getLogger("wind_alarm.azure.knowledge_base")

# Global clients cached
_cosmos_client = None
_blob_service_client = None


def get_cosmos_client():
    global _cosmos_client
    if _cosmos_client is None:
        endpoint = config.AZURE_COSMOS_ENDPOINT
        key = config.AZURE_COSMOS_KEY
        if key:
            _cosmos_client = CosmosClient(endpoint, credential=key)
        else:
            credential = DefaultAzureCredential()
            _cosmos_client = CosmosClient(endpoint, credential=credential)
    return _cosmos_client


def get_container():
    client = get_cosmos_client()
    db_name = config.AZURE_COSMOS_DB
    container_name = config.AZURE_COSMOS_CONTAINER
    
    database = client.get_database_client(db_name)
    container = database.get_container_client(container_name)
    return container


def get_blob_service_client():
    global _blob_service_client
    if _blob_service_client is None:
        conn_str = config.AZURE_STORAGE_CONNECTION_STRING
        if conn_str:
            _blob_service_client = BlobServiceClient.from_connection_string(conn_str)
        else:
            # Fallback to Azure Identity (requires STORAGE_ACCOUNT_URL or similar)
            # In local test environments, connection string is typically used
            account_url = os.environ.get("AZURE_STORAGE_ACCOUNT_URL")
            if account_url:
                credential = DefaultAzureCredential()
                _blob_service_client = BlobServiceClient(account_url, credential=credential)
            else:
                raise EnvironmentError("AZURE_STORAGE_CONNECTION_STRING or AZURE_STORAGE_ACCOUNT_URL must be set")
    return _blob_service_client


def save_measurement(state: dict) -> bool:
    try:
        container = get_container()
        observed_at = state.get("observed_at") or datetime.now(timezone.utc).isoformat()
        location_id = state.get("location_id", "default")
        
        # Cosmos DB requires a unique "id" field in JSON documents
        item = {
            "id": f"{location_id}-{observed_at}".replace(":", "-").replace("/", "-"),
            "location_id": location_id,
            "observed_at": observed_at,
            "base_wind_knots": float(state.get("base_wind_knots", 0.0)),
            "gust_knots": float(state.get("gust_knots", 0.0)),
            "threshold_exceeded": bool(state.get("threshold_exceeded", False)),
            "ttl": 90 * 24 * 60 * 60, # 90 days TTL
        }
        
        container.upsert_item(item)
        logger.info("Successfully persisted measurement to Cosmos DB for %s", location_id)
        return True
    except Exception as exc:
        logger.error("Failed to save measurement to Cosmos DB: %s", exc)
        return False


def get_recent_measurements(location_id: str, hours: int = 24) -> List[dict]:
    try:
        container = get_container()
        since = datetime.now(timezone.utc).timestamp() - (hours * 3600)
        since_iso = datetime.fromtimestamp(since, tz=timezone.utc).isoformat()
        
        # Safe parameterized query for Cosmos DB
        query = (
            "SELECT * FROM c WHERE c.location_id = @location_id "
            "AND c.observed_at >= @since_iso"
        )
        parameters = [
            {"name": "@location_id", "value": location_id},
            {"name": "@since_iso", "value": since_iso}
        ]
        
        items = list(container.query_items(
            query=query,
            parameters=parameters,
            enable_cross_partition_query=True
        ))
        
        # Sort in memory descending by observed_at
        items.sort(key=lambda x: x.get("observed_at", ""), reverse=True)
        return items
    except Exception as exc:
        logger.error("Failed to query Cosmos DB: %s", exc)
        return []


def get_average_wind(location_id: str, hours: int = 24) -> Optional[float]:
    measurements = get_recent_measurements(location_id, hours)
    winds = [m["base_wind_knots"] for m in measurements if m.get("base_wind_knots", 0.0) > 0]
    return sum(winds) / len(winds) if winds else None


def _upload_to_blob(key: str, data_dict: Any) -> None:
    try:
        container_name = config.AZURE_STORAGE_CONTAINER_NAME
        blob_service_client = get_blob_service_client()
        
        # Get blob client
        blob_client = blob_service_client.get_blob_client(container=container_name, blob=key)
        
        # Serialize to JSON string
        payload = json.dumps(data_dict, indent=2, ensure_ascii=False)
        
        # Upload (overwrite if exists)
        blob_client.upload_blob(payload, overwrite=True, content_type="application/json")
        logger.info("Successfully updated %s in Azure Blob Storage", key)
    except Exception as exc:
        logger.error("Failed to write %s to Azure Blob Storage: %s", key, exc)


def update_blob_measurements(location_id: str, aggregated_data: dict) -> None:
    # First get the current measurements.json from Blob if it exists to merge
    key = "measurements.json"
    current_data = {}
    
    try:
        container_name = config.AZURE_STORAGE_CONTAINER_NAME
        blob_service_client = get_blob_service_client()
        blob_client = blob_service_client.get_blob_client(container=container_name, blob=key)
        
        if blob_client.exists():
            download_stream = blob_client.download_blob()
            current_data = json.loads(download_stream.readall().decode("utf-8"))
    except Exception as exc:
        logger.info("No existing measurements.json found or failed to read: %s. Creating new.", exc)
        
    current_data[location_id] = aggregated_data
    _upload_to_blob(key, current_data)


def update_blob_forecast(location_id: str, forecast_data: dict) -> None:
    key = "forecast.json"
    current_data = {}
    
    try:
        container_name = config.AZURE_STORAGE_CONTAINER_NAME
        blob_service_client = get_blob_service_client()
        blob_client = blob_service_client.get_blob_client(container=container_name, blob=key)
        
        if blob_client.exists():
            download_stream = blob_client.download_blob()
            current_data = json.loads(download_stream.readall().decode("utf-8"))
    except Exception as exc:
        logger.info("No existing forecast.json found or failed to read: %s. Creating new.", exc)
        
    current_data[location_id] = forecast_data
    _upload_to_blob(key, current_data)


def update_blob_history(location_id: str) -> None:
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
        _upload_to_blob(key, history_list)
    except Exception as exc:
        logger.error("Failed to update S3 history file %s: %s", key, exc)
