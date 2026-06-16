"""
Unit tests for the forecast module.
"""
from unittest.mock import patch, MagicMock
import pytest

from wind_alarm.forecast.forecast_sources import FORECAST_SOURCES
from wind_alarm.forecast.forecast_scraper import scrape_forecast_sources
from wind_alarm.forecast.forecast_analyzer import analyze_forecasts
from wind_alarm.forecast.forecast_runner import run_forecast


def test_forecast_sources_config():
    """Verify forecast sources configuration is defined for locations."""
    assert "gardasee" in FORECAST_SOURCES
    assert "kochelsee" in FORECAST_SOURCES
    
    gardasee_sources = FORECAST_SOURCES["gardasee"]
    assert len(gardasee_sources) == 4
    assert any(s["id"] == "foehn_diagram" for s in gardasee_sources)
    assert any(s["id"] == "windguru_arome" for s in gardasee_sources)

    kochelsee_sources = FORECAST_SOURCES["kochelsee"]
    assert len(kochelsee_sources) == 4
    assert any(s["id"] == "patscherkofel" for s in kochelsee_sources)
    assert any(s["id"] == "foehn_diagram" for s in kochelsee_sources)


@patch("wind_alarm.forecast.forecast_scraper.sync_playwright")
def test_scrape_forecast_sources(mock_playwright):
    """Test that scraper works and calls browser methods."""
    # Mock playwright structure
    mock_pw = MagicMock()
    mock_playwright.return_value.__enter__.return_value = mock_pw
    
    mock_browser = MagicMock()
    mock_pw.chromium.launch.return_value = mock_browser
    
    mock_context = MagicMock()
    mock_browser.new_context.return_value = mock_context
    
    mock_page = MagicMock()
    mock_context.new_page.return_value = mock_page
    
    # Run scraper
    res = scrape_forecast_sources("kochelsee")
    
    # Assert pages were created and screenshotted
    assert mock_page.goto.call_count == 4
    assert mock_page.screenshot.call_count == 4
    assert "windfinder_forecast" in res
    assert "windfinder_superforecast" in res
    assert "patscherkofel" in res
    assert "foehn_diagram" in res


def test_analyze_forecasts_local_mode():
    """Test analyzer behavior in local mode (USE_AWS = False)."""
    with patch("wind_alarm.config.config.USE_AWS", False):
        res = analyze_forecasts("gardasee", {"windfinder_forecast": "/tmp/test.png"})
        assert res["confidence"] == "high"
        assert res["wind_probability_percent"] == 85
        assert len(res["sources_analyzed"]) > 0


@patch("boto3.client")
def test_analyze_forecasts_aws_mode(mock_boto_client):
    """Test analyzer behavior in AWS mode (USE_AWS = True) with Bedrock response mocked."""
    # Mock Bedrock Runtime Converse response
    mock_client = MagicMock()
    mock_boto_client.return_value = mock_client
    
    mock_response = {
        "output": {
            "message": {
                "content": [
                    {
                        "text": '{"summary": "Starker Pelér am Vormittag.", "wind_probability_percent": 90, "confidence": "high", "expected_wind_knots": {"min": 15, "max": 25}, "expected_direction": "N", "best_time_window": "06:00 - 10:00", "model_consensus": "Sehr gut", "sources_analyzed": []}'
                    }
                ]
            }
        }
    }
    mock_client.converse.return_value = mock_response

    with patch("wind_alarm.config.config.USE_AWS", True), \
         patch("builtins.open", MagicMock()), \
         patch("os.path.exists", return_value=True):
        
        res = analyze_forecasts("gardasee", {"foehn_diagram": "/tmp/test.png"})
        assert res["wind_probability_percent"] == 90
        assert res["confidence"] == "high"
        assert res["expected_wind_knots"]["min"] == 15
        assert res["expected_wind_knots"]["max"] == 25
        assert res["expected_direction"] == "N"
