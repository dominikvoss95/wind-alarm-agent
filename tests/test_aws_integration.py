"""
Integration tests for AWS components.
"""
import json
from unittest.mock import patch, MagicMock


class TestKnowledgeBase:
    @patch("aws.knowledge_base.dynamodb")
    def test_save_measurement(self, mock_dyn):
        from aws.knowledge_base import save_measurement
        mock_table = MagicMock()
        mock_dyn.Table.return_value = mock_table
        state = {"location_id": "kochelsee", "base_wind_knots": 15.0}
        assert save_measurement(state) is True
        mock_table.put_item.assert_called_once()

    @patch("aws.knowledge_base.get_table")
    def test_save_measurement_replaces_missing_timestamp(self, mock_get_table):
        from aws.knowledge_base import save_measurement
        mock_table = MagicMock()
        mock_get_table.return_value = mock_table
        save_measurement({
            "location_id": "kochelsee",
            "observed_at": None,
            "base_wind_knots": 5.0,
        })
        item = mock_table.put_item.call_args.kwargs["Item"]
        assert item["observed_at"]
        assert item["location_id"] == "kochelsee"

    @patch("aws.knowledge_base.boto3.client")
    def test_s3_payload_includes_client_fields(self, mock_boto_client):
        from aws.knowledge_base import update_s3_measurements
        mock_s3 = MagicMock()
        mock_boto_client.return_value = mock_s3
        mock_s3.get_object.side_effect = Exception("missing")
        with patch("aws.knowledge_base.bucket_name", "wind-bucket"):
            update_s3_measurements("kochelsee", {
                "base_wind_knots": 11.0,
                "gust_knots": 14.0,
                "parse_status": "success",
                "is_fresh": True,
                "threshold_exceeded": True,
            })
        body = json.loads(mock_s3.put_object.call_args.kwargs["Body"])
        stored = body["kochelsee"]
        assert stored["base_wind"] == 11.0
        assert stored["gust"] == 14.0
        assert stored["fetch_status"] == "success"
        assert stored["updated_at"]


class TestGuardrails:
    def test_validate_state_valid(self):
        from aws.guardrails import validate_state
        state = {"location_id": "kochelsee", "threshold_knots": 12.0, "freshness_limit_minutes": 60}
        is_valid, _ = validate_state(state)
        assert is_valid is True

    def test_validate_state_xss(self):
        from aws.guardrails import validate_state
        state = {"location_id": "kochelsee<script>alert(1)</script>", "threshold_knots": 12.0}
        is_valid, error = validate_state(state)
        assert is_valid is False


class TestOrchestrator:
    @patch.dict("os.environ", {"WIND_ALARM_ORCHESTRATOR": "langgraph"})
    def test_langgraph_orchestrator(self):
        from wind_alarm.orchestrator import get_orchestrator
        orch = get_orchestrator()
        assert orch.get_name() == "LangGraph"