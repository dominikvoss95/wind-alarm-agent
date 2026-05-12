"""
LangGraph-based orchestrator for local execution.
"""
from wind_alarm.graph import build_wind_alarm_graph
from wind_alarm.state import WindGraphState
from wind_alarm.orchestrator import OrchestratorBase


class LangGraphOrchestrator(OrchestratorBase):
    def __init__(self):
        self.app = build_wind_alarm_graph()
    def invoke(self, state: WindGraphState) -> WindGraphState:
        return self.app.invoke(state)
    def get_name(self) -> str:
        return "LangGraph"