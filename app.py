"""
Main entry point to run the Wind Alarm Agent.
Supports LangGraph (local) and Bedrock Agents (AWS) via WIND_ALARM_ORCHESTRATOR.
"""
import argparse
import os
import time
from wind_alarm.config import config
from wind_alarm.logger import configure_logging
from wind_alarm.run_report import format_summary, measurement_exit_code, write_step_summary


def main():
    configure_logging()
    parser = argparse.ArgumentParser(description="Run the Wind Alarm Agent.")
    parser.add_argument("--api", action="store_true", help="Serve the HTTP API instead of running a check")
    parser.add_argument("--host", type=str, default=os.environ.get("HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8000")))
    parser.add_argument("--location", type=str, default="kochelsee", choices=["kochelsee", "gardasee"])
    parser.add_argument(
        "--threshold",
        type=float,
        default=None,
        help="Knots the base wind must exceed. Defaults to the location setting (10 Kochelsee, 12 Gardasee).",
    )
    parser.add_argument("--freshness", type=int, default=60)
    parser.add_argument(
        "--orchestrator",
        type=str,
        default=None,
        choices=["langgraph", "bedrock"],
        help="Override WIND_ALARM_ORCHESTRATOR / USE_AWS selection",
    )
    parser.add_argument("--loop", action="store_true")
    parser.add_argument("--interval", type=int, default=30)
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Compare station JSON with the overlay and exit. Does not send a push.",
    )

    args = parser.parse_args()

    if args.verify:
        from wind_alarm.verify import exit_code, verify_locations
        reports = verify_locations([args.location], run_ocr=True)
        for report in reports:
            print(
                f"{report.get('slug')}: station={report.get('station_wind')} "
                f"overlay={report.get('overlay_wind')} agree={report.get('agree')} "
                f"({report.get('detail')})"
            )
        raise SystemExit(exit_code(reports))

    if args.api:
        import uvicorn
        uvicorn.run("wind_alarm.api:app", host=args.host, port=args.port)
        return

    location_cfg = config.LOCATIONS.get(args.location)
    if not location_cfg:
        print(f"Error: Unknown location '{args.location}'")
        raise SystemExit(2)
    if args.threshold is None:
        args.threshold = float(location_cfg["threshold_knots"])

    from wind_alarm.orchestrator import get_orchestrator

    try:
        orchestrator = get_orchestrator(args.orchestrator)
        print(f"Using orchestrator: {orchestrator.get_name()}")
    except EnvironmentError as exc:
        print(f"ERROR: {exc}")
        return

    from wind_alarm.aggregator import run_and_aggregate_measurements

    print(
        f"Starting Wind Alarm Agent for {location_cfg['name']} "
        f"threshold>{args.threshold:g} freshness={args.freshness}m"
    )

    exit_code = 2
    while True:
        result = run_and_aggregate_measurements(
            location_id=args.location,
            threshold=args.threshold,
            freshness=args.freshness,
            orchestrator=orchestrator,
        )
        webcams = result.get("webcams") or {}
        exit_code = result.get("run_exit_code")
        if exit_code is None:
            exit_code = measurement_exit_code([
                info.get("status", "fetch_failed") for info in webcams.values() if isinstance(info, dict)
            ])
        print(f"Aggregation complete. Threshold exceeded: {result.get('threshold_exceeded')}")
        for cam_id, info in webcams.items():
            if not isinstance(info, dict):
                print(f"  {cam_id}: fetch_failed")
                continue
            print(
                f"  {cam_id}: status={info.get('status')} "
                f"wind={info.get('base_wind')} gust={info.get('gust')} "
                f"at={info.get('observed_at')} source={info.get('reading_source')}"
            )
            if info.get("error_message"):
                print(f"    error: {info.get('error_message')}")
        write_step_summary(format_summary(args.location, args.threshold, webcams, exit_code))

        if not args.loop:
            raise SystemExit(exit_code)
        time.sleep(args.interval * 60)


if __name__ == "__main__":
    main()
