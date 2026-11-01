# 🌬️ Wind Alarm Agent

**Enterprise-Ready Wind Monitoring & Notification System.**

The agent reads the addicted-sports station feed for Kochelsee and Gardasee and sends one Firebase push per location per Berlin morning when a fresh base wind is over that spot's threshold. OCR of the webcam picture is only a cross-check. It cannot authorize an alarm.

## Architecture

```text
station JSON (wsavg / wsmax / utctstamp)
        |
        v
LangGraph: fetch -> parse -> freshness -> threshold -> one FCM push
        |
        +--> EventBridge every 5 minutes (primary, after terraform apply)
        +--> GitHub Actions every 15 minutes (backup)
```

A run with no fresh station reading exits non-zero. Schedules, the dead-man's switch, and what to do when no alarm arrives are in the [README](../README.md).

## Deployment

Apply Terraform for the EventBridge rules and CloudWatch alarms. Do not rely on GitHub cron alone. Details are in the [README](../README.md).
