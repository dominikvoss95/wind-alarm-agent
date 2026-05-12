"""
Tests for multi-location support in the Wind Alarm Agent.
"""
from unittest.mock import patch, MagicMock
from wind_alarm.config import config
from wind_alarm.nodes import send_notification
from wind_alarm.state import WindGraphState
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

    import sys
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
