"""
Integration tests for AWS components.
"""
import pytest
from unittest.mock import patch, MagicMock


class TestKnowledgeBase:
    @patch("src.aws.knowledge_base.dynamodb")
    def test_save_measurement(self, mock_dyn):
        from src.aws.knowledge_base import save_measurement
        mock_table = MagicMock()
        mock_dyn.Table.return_value = mock_table
        state = {"location_id": "kochelsee", "base_wind_knots": 15.0}
        assert save_measurement(state) is True
        mock_table.put_item.assert_called_once()


class TestGuardrails:
    def test_validate_state_valid(self):
        from src.aws.guardrails import validate_state
        state = {"location_id": "kochelsee", "threshold_knots": 12.0, "freshness_limit_minutes": 60}
        is_valid, _ = validate_state(state)
        assert is_valid is True

    def test_validate_state_xss(self):
        from src.aws.guardrails import validate_state
        state = {"location_id": "kochelsee<script>alert(1)</script>", "threshold_knots": 12.0}
        is_valid, error = validate_state(state)
        assert is_valid is False


class TestOrchestrator:
    @patch.dict("os.environ", {"WIND_ALARM_ORCHESTRATOR": "langgraph"})
    def test_langgraph_orchestrator(self):
        from wind_alarm.orchestrator import get_orchestrator
        orch = get_orchestrator()
        assert orch.get_name() == "LangGraph"