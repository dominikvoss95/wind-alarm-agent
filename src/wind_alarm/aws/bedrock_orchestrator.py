"""
Bedrock Agents orchestrator for AWS execution.
"""
import os
import json
import boto3
from datetime import datetime, timezone
from wind_alarm.state import WindGraphState
from wind_alarm.orchestrator import OrchestratorBase


class BedrockOrchestrator(OrchestratorBase):
    def __init__(self):
        self.agent_id = os.environ.get("BEDROCK_AGENT_ID")
        self.agent_alias = os.environ.get("BEDROCK_AGENT_ALIAS", "TSTALIASID")
        if not self.agent_id:
            raise EnvironmentError("BEDROCK_AGENT_ID not set")
        self.client = boto3.client("bedrock-agent-runtime", region_name=os.environ.get("AWS_REGION", "eu-central-1"))

    def invoke(self, state: WindGraphState) -> WindGraphState:
        input_data = json.dumps({
            "action": "check_wind",
            "source_identifier": state.get("source_identifier"),
            "location_id": state.get("location_id", "default"),
            "threshold_knots": state.get("threshold_knots", 10.0),
            "freshness_limit_minutes": state.get("freshness_limit_minutes", 60),
        })
        session_id = f"wind-alarm-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}"
        response = self.client.invoke_agent(
            agentId=self.agent_id, agentAliasId=self.agent_alias,
            sessionId=session_id, inputText=input_data,
        )
        completion_chunks = response.get("completion", [])
        raw_response = "".join(
            chunk.get("chunk", {}).get("bytes", b"").decode("utf-8", errors="replace")
            for chunk in completion_chunks
        )
        try:
            return WindGraphState(**json.loads(raw_response))
        except (json.JSONDecodeError, TypeError):
            return WindGraphState(fetch_status="failed", error_message=f"Bedrock unparseable: {raw_response[:500]}")

    def get_name(self) -> str:
        return "Bedrock Agents"