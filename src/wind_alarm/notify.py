"""FCM payloads that iOS will actually present.

A data-only message is dropped when the app is backgrounded or killed unless
the APNs payload is an alert with content-available. The sound file is the
one bundled in the iOS app (alarm_sound.mp3). Time Sensitive does not need
Apple's critical-alerts entitlement; critical alerts do, and that entitlement
is not in this project.
"""

from __future__ import annotations

from firebase_admin import messaging

ALARM_SOUND = "alarm_sound.mp3"
EXPECTED_BUNDLE_ID = "de.dominikvoss.wind-alarm"


def build_alarm_message(
    *,
    topic: str,
    title: str,
    body: str,
    location_id: str,
    wind_knots: float,
) -> messaging.Message:
    """One visible, high-priority alert for a location topic."""
    wind_text = _format_knots(wind_knots)
    return messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data={
            "action": "schedule_alarm",
            "location": location_id,
            "wind": wind_text,
        },
        topic=topic,
        android=messaging.AndroidConfig(priority="high"),
        apns=messaging.APNSConfig(
            headers={
                "apns-priority": "10",
                "apns-push-type": "alert",
            },
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    sound=ALARM_SOUND,
                    content_available=True,
                    mutable_content=True,
                    custom_data={"interruption-level": "time-sensitive"},
                )
            ),
        ),
    )


def _format_knots(wind_knots: float) -> str:
    if float(wind_knots).is_integer():
        return str(int(wind_knots))
    return str(wind_knots)
