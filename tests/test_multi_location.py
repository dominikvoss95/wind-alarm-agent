"""
Tests for multi-location support in the Wind Alarm Agent.
"""
import sys
from datetime import datetime, timezone
from unittest.mock import patch, MagicMock
from wind_alarm.config import config
from wind_alarm.nodes import send_notification
from wind_alarm.state import WindGraphState
from wind_alarm.aggregator import run_and_aggregate_measurements
from app import main

def test_config_locations_exist():
    """Verify LOCATIONS dict has the expected keys and structure."""
    assert "kochelsee" in config.LOCATIONS
    assert "gardasee" in config.LOCATIONS
    assert len(config.LOCATIONS["kochelsee"]["urls"]) == 1
    assert len(config.LOCATIONS["gardasee"]["urls"]) == 3
    assert config.LOCATIONS["kochelsee"]["fcm_topic"] == "wind_alarms_kochelsee"
    assert config.LOCATIONS["gardasee"]["fcm_topic"] == "wind_alarms_gardasee"

@patch("wind_alarm.nodes.messaging.send")
def test_send_notification_uses_custom_topic(mock_send):
    """Test that send_notification uses the target_fcm_topic from state."""
    mock_send.return_value = "mock_response_id"
    custom_topic = "wind_alarms_gardasee"
    state = WindGraphState(
        threshold_exceeded=True, 
        base_wind_knots=15.0, 
        target_fcm_topic=custom_topic
    )
    result = send_notification(state)
    assert result.get("notification_sent") is True
    
    # Verify the message was sent to the custom topic
    args, kwargs = mock_send.call_args
    message = args[0]
    assert message.topic == custom_topic

@patch("wind_alarm.orchestrator.get_orchestrator")
@patch("app.time.sleep", side_effect=InterruptedError)
def test_app_gardasee_invokes_three_urls(mock_sleep, mock_get_orch):
    """Verify that running app for Gardasee invokes the orchestrator for all 3 URLs."""
    mock_orch = MagicMock()
    mock_orch.get_name.return_value = "LangGraph"
    mock_get_orch.return_value = mock_orch

    with patch.object(sys, 'argv', ['app.py', '--location', 'gardasee']):
        try:
            main()
        except SystemExit:
            pass

    assert mock_orch.invoke.call_count == 3
    for call in mock_orch.invoke.call_args_list:
        state = call[0][0]
        assert state["location_id"] == "gardasee"
        assert state["target_fcm_topic"] == "wind_alarms_gardasee"
        assert state["skip_notification"] is True


@patch("wind_alarm.aws.bedrock_orchestrator.BedrockOrchestrator")
@patch("wind_alarm.aggregator.run_and_aggregate_measurements", return_value={"threshold_exceeded": False, "webcams": {}})
def test_cli_orchestrator_flag_is_honored(mock_run, mock_bedrock_cls):
    """--orchestrator must select the backend instead of being ignored."""
    mock_bedrock_cls.return_value.get_name.return_value = "Bedrock Agents"
    with patch.object(sys, "argv", ["app.py", "--location", "kochelsee", "--orchestrator", "bedrock"]):
        main()
    mock_bedrock_cls.assert_called_once()
    assert mock_run.call_args.kwargs["orchestrator"] is mock_bedrock_cls.return_value


@patch("wind_alarm.nodes.messaging.send", return_value="projects/test/messages/1")
@patch("wind_alarm.config.config.initialize_firebase")
@patch("wind_alarm.graph.parse_primary_source")
@patch("wind_alarm.graph.fetch_primary_source")
def test_aggregator_sends_one_notification(mock_fetch, mock_parse, _mock_init, mock_send):
    """A fresh reading above the threshold sends the consolidated alert only."""
    observed = datetime.now(timezone.utc).isoformat()
    mock_fetch.return_value = {
        "fetch_status": "success",
        "raw_payload": "/tmp/shot.png",
        "fetched_at": observed,
        "error_message": "",
    }
    mock_parse.return_value = {
        "parse_status": "success",
        "observed_at": observed,
        "base_wind_knots": 20.0,
        "gust_knots": 24.0,
        "error_message": "",
    }
    from wind_alarm.local.langgraph_orchestrator import LangGraphOrchestrator

    result = run_and_aggregate_measurements(
        location_id="kochelsee",
        threshold=10.0,
        freshness=60,
        orchestrator=LangGraphOrchestrator(),
    )
    assert result["threshold_exceeded"] is True
    assert result["notification_sent"] is True
    assert mock_send.call_count == 1
