"""
Main entry point to run the Wind Alarm Agent.
"""
import argparse
import time
import threading
from wind_alarm.graph import build_wind_alarm_graph
from wind_alarm.state import WindGraphState
from wind_alarm.config import config

try:
    import uvicorn
    from wind_alarm.api import app as fastapi_app
    API_AVAILABLE = True
except ImportError:
    API_AVAILABLE = False
    fastapi_app = None


def run_api_server():
    """Run the FastAPI server in a separate thread."""
    if API_AVAILABLE:
        uvicorn.run(fastapi_app, host="0.0.0.0", port=8000, log_level="info")
    else:
        print("FastAPI not installed. Install with: pip install fastapi uvicorn")


def main():
    parser = argparse.ArgumentParser(description="Run the Kochelsee Wind Alarm Agent.")
    parser.add_argument(
        "--location",
        type=str,
        default="kochelsee",
        choices=["kochelsee", "gardasee"],
        help="The location to monitor."
    )
    parser.add_argument(
        "--threshold", 
        type=float, 
        default=12.0, 
        help="Wind threshold in knots."
    )
    parser.add_argument(
        "--freshness", 
        type=int, 
        default=60, 
        help="Max age of data in minutes."
    )
    parser.add_argument(
        "--token", 
        type=str, 
        help="The target FCM token to send the notification to."
    )
    parser.add_argument(
        "--loop", 
        action="store_true", 
        help="Run in a loop indefinitely."
    )
    parser.add_argument(
        "--interval", 
        type=int, 
        default=30, 
        help="Interval between checks in minutes (only if --loop is used)."
    )
    parser.add_argument(
        "--api", 
        action="store_true", 
        help="Start the REST API server."
    )
    
    args = parser.parse_args()

    location_cfg = config.LOCATIONS.get(args.location)
    if not location_cfg:
        print(f"Error: Unknown location '{args.location}'")
        return

    # Start API server in background thread if requested
    if args.api:
        api_thread = threading.Thread(target=run_api_server, daemon=True)
        api_thread.start()
        print("--- API server started on http://localhost:8000 ---")

    # Initialize graph
    app = build_wind_alarm_graph()
    
    print(f"--- Starting Wind Alarm Agent for {location_cfg['name']} ---")
    if args.loop:
        print(f"Monitoring mode: active (Interval: {args.interval} min)")
    
    while True:
        current_time = time.strftime('%H:%M:%S')
        print(f"\n[{current_time}] Checking wind for {location_cfg['name']}...")
        
        any_exceeded = False
        
        for url in location_cfg["urls"]:
            print(f"Checking URL: {url}")
            initial_state = WindGraphState(
                source_identifier=url,
                location_id=args.location,
                target_fcm_topic=location_cfg["fcm_topic"],
                threshold_knots=args.threshold,
                freshness_limit_minutes=args.freshness,
            )

            try:
                result = app.invoke(initial_state)

                print(f"  Result: {result.get('base_wind_knots')} kts (Limit: {'Exceeded' if result.get('threshold_exceeded') else 'OK'})")
                
                if result.get('threshold_exceeded'):
                    any_exceeded = True

                if result.get('error_message'):
                    print(f"  ERROR: {result.get('error_message')}")
                    
            except Exception as e:
                print(f"  CRITICAL ERROR checking {url}: {e}")

        if not args.loop:
            break
            
        print(f"Sleeping for {args.interval} minutes... (Ctrl+C to stop)")
        time.sleep(args.interval * 60)

if __name__ == "__main__":
    main()
