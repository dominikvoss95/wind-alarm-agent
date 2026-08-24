"""
Integration and unit tests for Azure components.
"""
import pytest
import os
import json
from unittest.mock import patch, MagicMock

from wind_alarm.config import config
from wind_alarm.state import WindGraphState


class TestAzureKnowledgeBase:
    @patch("azure.knowledge_base.get_container")
    def test_save_measurement(self, mock_get_container):
        from azure.knowledge_base import save_measurement
        mock_container = MagicMock()
        mock_get_container.return_value = mock_container
        
        state = {"location_id": "kochelsee", "base_wind_knots": 15.0}
        assert save_measurement(state) is True
        mock_container.upsert_item.assert_called_once()

    @patch("azure.knowledge_base.get_container")
    def test_get_recent_measurements(self, mock_get_container):
        from azure.knowledge_base import get_recent_measurements
        mock_container = MagicMock()
        mock_get_container.return_value = mock_container
        mock_container.query_items.return_value = [
            {"location_id": "kochelsee", "observed_at": "2026-08-24T22:00:00Z", "base_wind_knots": 12.0}
        ]
        
        items = get_recent_measurements("kochelsee", hours=2)
        assert len(items) == 1
        assert items[0]["base_wind_knots"] == 12.0
        mock_container.query_items.assert_called_once()

    @patch("azure.knowledge_base.get_blob_service_client")
    def test_update_blob_measurements(self, mock_get_blob_service):
        from azure.knowledge_base import update_blob_measurements
        
        mock_service = MagicMock()
        mock_blob = MagicMock()
        mock_get_blob_service.return_value = mock_service
        mock_service.get_blob_client.return_value = mock_blob
        mock_blob.exists.return_value = False
        
        aggregated = {"base_wind_knots": 10.0}
        update_blob_measurements("kochelsee", aggregated)
        mock_blob.upload_blob.assert_called_once()


class TestAzureOpenAIIntegration:
    @patch("openai.AzureOpenAI")
    @patch.dict("os.environ", {"USE_AZURE": "true", "AZURE_OPENAI_ENDPOINT": "https://test.openai.azure.com/"})
    def test_parse_primary_source_azure_openai(self, mock_azure_openai_class):
        from wind_alarm.nodes import parse_primary_source
        
        mock_client = MagicMock()
        mock_azure_openai_class.return_value = mock_client
        
        mock_response = MagicMock()
        mock_response.choices = [
            MagicMock(message=MagicMock(content='{"wind": 15, "gust": 20}'))
        ]
        mock_client.chat.completions.create.return_value = mock_response

        # Mock image open and patch config values to prevent modifying the global singleton
        with patch("wind_alarm.config.config.USE_AZURE", True), \
             patch("wind_alarm.config.config.AZURE_OPENAI_ENDPOINT", "https://test.openai.azure.com/"), \
             patch("wind_alarm.config.config.AZURE_OPENAI_DEPLOYMENT_NAME", "gpt-4o-mini"), \
             patch("wind_alarm.config.config.AZURE_OPENAI_KEY", "test-key"), \
             patch("builtins.open", MagicMock(return_value=MagicMock(__enter__=MagicMock(return_value=MagicMock(read=MagicMock(return_value=b"test-bytes")))))):
            
            state = WindGraphState(
                fetch_status="success",
                raw_payload="/tmp/mock.png",
                source_identifier="https://example.com"
            )
            result = parse_primary_source(state)
            
            assert result.get("parse_status") == "success"
            assert result.get("base_wind_knots") == 15.0
            assert result.get("gust_knots") == 20.0
            mock_client.chat.completions.create.assert_called_once()


class TestAzureOpenAIForecastAnalysis:
    @patch("openai.AzureOpenAI")
    @patch.dict("os.environ", {"USE_AZURE": "true", "AZURE_OPENAI_ENDPOINT": "https://test.openai.azure.com/"})
    def test_analyze_forecasts_azure_openai(self, mock_azure_openai_class):
        from wind_alarm.forecast.forecast_analyzer import analyze_forecasts
        
        mock_client = MagicMock()
        mock_azure_openai_class.return_value = mock_client
        
        mock_response = MagicMock()
        mock_response.choices = [
            MagicMock(message=MagicMock(content=json.dumps({
                "summary": "Föhnsturm voraus",
                "wind_probability_percent": 90,
                "confidence": "high",
                "expected_wind_knots": {"min": 15, "max": 25},
                "expected_direction": "S",
                "best_time_window": "12:00 - 16:00",
                "model_consensus": "Konsens vorhanden",
                "sources_analyzed": []
            })))
        ]
        mock_client.chat.completions.create.return_value = mock_response

        with patch("wind_alarm.config.config.USE_AZURE", True), \
             patch("wind_alarm.config.config.AZURE_OPENAI_ENDPOINT", "https://test.openai.azure.com/"), \
             patch("wind_alarm.config.config.AZURE_OPENAI_DEPLOYMENT_NAME", "gpt-4o-mini"), \
             patch("wind_alarm.config.config.AZURE_OPENAI_KEY", "test-key"), \
             patch("os.path.exists", return_value=True), \
             patch("builtins.open", MagicMock(return_value=MagicMock(__enter__=MagicMock(return_value=MagicMock(read=MagicMock(return_value=b"test-bytes")))))):
                
                screenshots = {"source1": "/tmp/img1.png"}
                result = analyze_forecasts("kochelsee", screenshots)
                
                assert result.get("wind_probability_percent") == 90
                assert result.get("expected_direction") == "S"
                mock_client.chat.completions.create.assert_called_once()
