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

@patch("app.build_wind_alarm_graph")
@patch("app.time.sleep", side_effect=InterruptedError) # To break the loop if --loop used, but here we test non-loop
def test_app_gardasee_invokes_three_urls(mock_sleep, mock_build_graph):
    """Verify that running app for Gardasee invokes the graph for all 3 URLs."""
    mock_app = MagicMock()
    mock_build_graph.return_value = mock_app
    mock_app.invoke.return_value = {"threshold_exceeded": False, "base_wind_knots": 5.0}

    import sys
    with patch.object(sys, 'argv', ['app.py', '--location', 'gardasee']):
         try:
             main()
         except SystemExit:
             pass
    
    # Should be called 3 times (one for each Gardasee URL)
    assert mock_app.invoke.call_count == 3
    
    # Check that location_id and target_fcm_topic were passed correctly in state
    for call in mock_app.invoke.call_args_list:
        state = call[0][0]
        assert state["location_id"] == "gardasee"
        assert state["target_fcm_topic"] == "wind_alarms_gardasee"
