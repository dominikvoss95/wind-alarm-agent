"""
Main entry point to run the Wind Alarm Agent.
Supports LangGraph (local) and Bedrock Agents (AWS) via WIND_ALARM_ORCHESTRATOR.
"""
import argparse
import os
import time
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

    from wind_alarm.aggregator import run_and_aggregate_measurements

    print(f"Starting Wind Alarm Agent for {location_cfg['name']}")

    while True:
        result = run_and_aggregate_measurements(
            location_id=args.location,
            threshold=args.threshold,
            freshness=args.freshness,
            orchestrator=orchestrator,
        )
        print(f"Aggregation complete. Threshold exceeded: {result.get('threshold_exceeded')}")
        for cam_id, info in result.get("webcams", {}).items():
            print(f"  {cam_id}: {info.get('base_wind')} kts (fresh: {info.get('is_fresh')})")

        if not args.loop:
            break
        time.sleep(args.interval * 60)


if __name__ == "__main__":
    main()