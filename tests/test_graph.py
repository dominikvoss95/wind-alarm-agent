"""
Tests for wind_alarm graph assembly.
"""
from wind_alarm.graph import build_wind_alarm_graph
from wind_alarm.state import WindGraphState


def test_graph_compilation():
    """Ensure the graph compiles successfully and has the right structure."""
    app = build_wind_alarm_graph()
    assert app is not None


def test_full_graph_execution_skipped_fetch():
    """Test full execution where the source URL is missing."""
    app = build_wind_alarm_graph()
    initial_state = WindGraphState(
        source_identifier="",
        threshold_knots=10,
        freshness_limit_minutes=60
    )
    result = app.invoke(initial_state)

    assert result.get("fetch_status") == "failed"
    assert result.get("parse_status") == "skipped"
    assert result.get("is_fresh") is False
    assert result.get("threshold_exceeded") is False
    assert result.get("notification_sent") is False
