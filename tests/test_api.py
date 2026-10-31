"""Tests for the measurement API."""
import json
from unittest.mock import patch

from fastapi.testclient import TestClient

from wind_alarm import api


def test_trigger_uses_json_body():
    """The posted threshold and freshness must reach the aggregator."""
    api.API_KEY = "test-key"
    captured = {}

    def fake_run(**kwargs):
        captured["location_id"] = kwargs["location_id"]
        captured["threshold"] = kwargs["threshold"]
        captured["freshness"] = kwargs["freshness"]
        return {"threshold_exceeded": True}

    with patch("wind_alarm.aggregator.run_and_aggregate_measurements", fake_run):
        client = TestClient(api.app)
        response = client.post(
            "/trigger/kochelsee",
            json={"threshold": 10.5, "freshness": 15},
            headers={"X-API-Key": "test-key"},
        )

    assert response.status_code == 200
    assert captured == {"location_id": "kochelsee", "threshold": 10.5, "freshness": 15}
    assert response.json()["threshold_exceeded"] is True


def test_history_reads_azure_when_enabled():
    api.API_KEY = "test-key"
    items = [{
        "observed_at": "2026-08-24T22:00:00+00:00",
        "base_wind_knots": 9.0,
        "gust_knots": 12.0,
    }]
    with patch("wind_alarm.config.config.USE_AWS", False), \
         patch("wind_alarm.config.config.USE_AZURE", True), \
         patch("azure.knowledge_base.get_recent_measurements", return_value=items):
        client = TestClient(api.app)
        response = client.get(
            "/measurements/kochelsee/history?hours=6",
            headers={"X-API-Key": "test-key"},
        )

    assert response.status_code == 200
    body = response.json()
    assert body[0]["base_wind"] == 9.0
    assert body[0]["gust"] == 12.0


def test_lambda_handler_aggregates_once():
    from handlers.lambda_handler import lambda_handler

    aggregated = {
        "threshold_exceeded": True,
        "notification_sent": True,
        "webcams": {"trimini": {"base_wind": 15.0, "is_fresh": True}},
    }
    with patch("wind_alarm.orchestrator.get_orchestrator", return_value=object()), \
         patch("wind_alarm.aggregator.run_and_aggregate_measurements", return_value=aggregated) as mock_run:
        result = lambda_handler({"location": "kochelsee", "threshold_knots": 10}, None)

    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    assert body["threshold_exceeded"] is True
    assert body["results"][0]["base_wind_knots"] == 15.0
    assert mock_run.call_args.kwargs["threshold"] == 10
