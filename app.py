"""
Main entry point to run the Wind Alarm Agent.
"""
import argparse
import json
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
    
    args = parser.parse_args()

    # Initialize graph
    app = build_wind_alarm_graph()
    
    initial_state = WindGraphState(
        source_identifier=args.url,
        threshold_knots=args.threshold,
        freshness_limit_minutes=args.freshness
    )

    print(f"--- Starting Wind Alarm Agent for {args.url} ---")
    print(f"Threshold: {args.threshold} kts | Freshness Limit: {args.freshness} min\n")

    # Run the graph
    result = app.invoke(initial_state)

    # Output formatted results
    print("--- Results ---")
    print(f"Fetch Status:    {result.get('fetch_status')}")
    print(f"Parse Status:    {result.get('parse_status')}")
    
    if result.get('parse_status') == 'success':
        print(f"Observed At:     {result.get('observed_at')}")
        print(f"Wind Speed:      {result.get('base_wind_knots')} kts")
        print(f"Gusts:           {result.get('gust_knots')} kts")
        print(f"Data Fresh:      {result.get('is_fresh')}")
        print(f"Limit Exceeded:  {result.get('threshold_exceeded')}")
        print(f"Notification:    {'SENT' if result.get('notification_sent') else 'None'}")
    
    if result.get('error_message'):
        print(f"\nERROR: {result.get('error_message')}")

if __name__ == "__main__":
    main()
