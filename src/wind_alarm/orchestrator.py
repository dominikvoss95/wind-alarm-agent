"""
Orchestrator abstraction layer.
Switch between LangGraph (local) and Bedrock Agents (AWS) via env var.
"""
import os
from wind_alarm.state import WindGraphState


ORCHESTRATOR_MODE = os.environ.get("WIND_ALARM_ORCHESTRATOR", "langgraph")


def get_orchestrator():
    if ORCHESTRATOR_MODE == "bedrock":
        from wind_alarm.aws.bedrock_orchestrator import BedrockOrchestrator
        return BedrockOrchestrator()
    else:
        from wind_alarm.local.langgraph_orchestrator import LangGraphOrchestrator
        return LangGraphOrchestrator()


class OrchestratorBase:
    def invoke(self, state: WindGraphState) -> WindGraphState:
        raise NotImplementedError
    def get_name(self) -> str:
        raise NotImplementedError


def run_wind_alarm(state: WindGraphState) -> WindGraphState:
    orchestrator = get_orchestrator()
    return orchestrator.invoke(state)