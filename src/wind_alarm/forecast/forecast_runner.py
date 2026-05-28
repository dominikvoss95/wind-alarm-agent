"""
Runner module orchestrating the forecast pipeline.
"""
import logging
from datetime import datetime, timezone
from typing import Dict, Any

from wind_alarm.config import config
from wind_alarm.forecast.forecast_scraper import scrape_forecast_sources
from wind_alarm.forecast.forecast_analyzer import analyze_forecasts

logger = logging.getLogger("wind_alarm.forecast_runner")

def run_forecast(location_id: str) -> Dict[str, Any]:
    """
    Executes the full forecast pipeline:
    1. Scrapes screenshots of various sources.
    2. Sends them to Bedrock for analysis.
    3. Saves result locally and uploads to S3.
    """
    logger.info("Starting forecast pipeline for location: %s", location_id)
    
    # 1. Scrape
    screenshots = scrape_forecast_sources(location_id)
    
    # 2. Analyze
    forecast_result = analyze_forecasts(location_id, screenshots)
    
    # Add metadata
    forecast_result["updated_at"] = datetime.now(timezone.utc).isoformat()
    
    # 3. Persist
    if config.USE_AWS:
        try:
            from aws.knowledge_base import update_s3_forecast
            update_s3_forecast(location_id, forecast_result)
            logger.info("Successfully updated forecast in S3 for %s", location_id)
        except Exception as exc:
            logger.error("Failed to update forecast in S3: %s", exc)
    else:
        # Local mode: write to local file
        local_path = config.WRITE_ROOT / f"forecast_{location_id}.json"
        try:
            import json
            with open(local_path, "w", encoding="utf-8") as f:
                json.dump(forecast_result, f, indent=2, ensure_ascii=False)
            logger.info("Successfully wrote local forecast to %s", local_path)
        except Exception as exc:
            logger.error("Failed to write local forecast file: %s", exc)
            
    return forecast_result
