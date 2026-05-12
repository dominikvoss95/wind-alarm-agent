"""
Main entry point to run the Wind Alarm Agent.
Supports LangGraph (local) and Bedrock Agents (AWS) via WIND_ALARM_ORCHESTRATOR.
"""
import argparse
import os
from wind_alarm.config import config


def main():
    parser = argparse.ArgumentParser(description="Run the Wind Alarm Agent.")
    parser.add_argument("--location", type=str, default="kochelsee", choices=["kochelsee", "gardasee"])
    parser.add_argument("--threshold", type=float, default=12.0)
    parser.add_argument("--freshness", type=int, default=60)
    parser.add_argument("--orchestrator", type=str, default=os.environ.get("WIND_ALARM_ORCHESTRATOR", "langgraph"))
    parser.add_argument("--loop", action="store_true")
    parser.add_argument("--interval", type=int, default=30)

    args = parser.parse_args()
    location_cfg = config.LOCATIONS.get(args.location)
    if not location_cfg:
        print(f"Error: Unknown location '{args.location}'")
        return

    from wind_alarm.orchestrator import get_orchestrator
    from wind_alarm.state import WindGraphState

    try:
        orchestrator = get_orchestrator()
        print(f"Using orchestrator: {orchestrator.get_name()}")
    except EnvironmentError as e:
        print(f"ERROR: {e}")
        return

    print(f"Starting Wind Alarm Agent for {location_cfg['name']}")

    import time
    while True:
        for url in location_cfg["urls"]:
            initial_state = WindGraphState(
                source_identifier=url,
                location_id=args.location,
                target_fcm_topic=location_cfg["fcm_topic"],
                threshold_knots=args.threshold,
                freshness_limit_minutes=args.freshness,
            )
            result = orchestrator.invoke(initial_state)
            print(f"  {url}: {result.get('base_wind_knots')} kts (exceeded: {result.get('threshold_exceeded')})")

        if not args.loop:
            break
        time.sleep(args.interval * 60)


if __name__ == "__main__":
    main()