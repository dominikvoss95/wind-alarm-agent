"""
Graph assembly for the Wind Alarm Agent.
"""
from langgraph.graph import StateGraph, START, END
from wind_alarm.state import WindGraphState

from wind_alarm.nodes import (
    fetch_primary_source,
    parse_primary_source,
    check_freshness,
    check_threshold,
    send_notification,
    save_to_firestore,
    save_measurement
)


def build_wind_alarm_graph():
    """
    Build and compile the deterministic wind alarm graph pipeline.
    """
    builder = StateGraph(WindGraphState)

    # Add nodes
    builder.add_node("fetch_primary_source", fetch_primary_source)
    builder.add_node("parse_primary_source", parse_primary_source)
    builder.add_node("check_freshness", check_freshness)
    builder.add_node("save_measurement", save_measurement)
    builder.add_node("save_to_firestore", save_to_firestore)
    builder.add_node("check_threshold", check_threshold)
    builder.add_node("send_notification", send_notification)

    # Define linear execution edges
    builder.add_edge(START, "fetch_primary_source")
    builder.add_edge("fetch_primary_source", "parse_primary_source")
    builder.add_edge("parse_primary_source", "check_freshness")
    builder.add_edge("check_freshness", "save_measurement")
    builder.add_edge("save_measurement", "save_to_firestore")
    builder.add_edge("save_to_firestore", "check_threshold")
    builder.add_edge("check_threshold", "send_notification")
    builder.add_edge("send_notification", END)

    return builder.compile()
