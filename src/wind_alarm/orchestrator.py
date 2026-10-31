import os
from wind_alarm.config import config
from wind_alarm.state import WindGraphState


def get_orchestrator(mode: str | None = None):
    """Resolve the orchestrator.

    An explicit mode (the CLI flag) wins, then WIND_ALARM_ORCHESTRATOR,
    then Bedrock when USE_AWS is set, otherwise LangGraph.
    """
    if not mode:
        mode = os.environ.get("WIND_ALARM_ORCHESTRATOR")
    if not mode:
        mode = "bedrock" if config.USE_AWS else "langgraph"
    
    if mode == "bedrock":
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