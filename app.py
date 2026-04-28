"""
Main entry point to run the Wind Alarm Agent.
"""
import argparse
import time
from wind_alarm.graph import build_wind_alarm_graph
from wind_alarm.state import WindGraphState

def main():
    parser = argparse.ArgumentParser(description="Run the Kochelsee Wind Alarm Agent.")
    parser.add_argument(
        "--url", 
        type=str, 
        default="https://www.addicted-sports.com/webcam/kochelsee/trimini/",
        help="The webcam URL to check."
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
    
    args = parser.parse_args()

    # Initialize graph
    app = build_wind_alarm_graph()
    
    print(f"--- Starting Wind Alarm Agent for {args.url} ---")
    if args.loop:
        print(f"Monitoring mode: active (Interval: {args.interval} min)")
    
    while True:
        initial_state = WindGraphState(
            source_identifier=args.url,
            threshold_knots=args.threshold,
            freshness_limit_minutes=args.freshness,
            target_fcm_token=args.token
        )

        current_time = time.strftime('%H:%M:%S')
        print(f"\n[{current_time}] Checking wind...")
        
        # Run the graph
        try:
            result = app.invoke(initial_state)

            # Output formatted results
            print("--- Results ---")
            print(f"Wind Speed:      {result.get('base_wind_knots')} kts")
            print(f"Limit Exceeded:  {result.get('threshold_exceeded')}")
            print(f"Notification:    {'SENT' if result.get('notification_sent') else 'None'}")
            
            if result.get('error_message'):
                print(f"ERROR: {result.get('error_message')}")
        except Exception as e:
            print(f"CRITICAL ERROR during execution: {e}")

        if not args.loop:
            break
            
        print(f"Sleeping for {args.interval} minutes... (Ctrl+C to stop)")
        time.sleep(args.interval * 60)

if __name__ == "__main__":
    main()
