"""
Node definitions for the Wind Alarm graph.
"""
import re
import time
from datetime import datetime, timezone

import cv2
import easyocr
import firebase_admin
from firebase_admin import credentials, messaging, firestore
from playwright.sync_api import sync_playwright

from wind_alarm.state import WindGraphState
from wind_alarm.config import config
from wind_alarm import store

# --- Firebase Initialization ---
# Configuration loaded from environment or default file
try:
    cred = credentials.Certificate(config.FIREBASE_CREDENTIALS_PATH)
    firebase_admin.initialize_app(cred)
except Exception as e:
    # Fallback/Log if credentials are missing. 
    # In production, we'd log this properly.
    print(f"Warning: Firebase not initialized: {e}")


def fetch_primary_source(state: WindGraphState) -> WindGraphState:
    """
    Fetch the raw wind data by taking a screenshot using Playwright.
    """
    source_url = state.get("source_identifier")
    if not source_url:
        return {
            "fetch_status": "failed",
            "error_message": "Missing source_identifier"
        }

    now = datetime.now(timezone.utc).isoformat()
    location_id = state.get("location_id", "default")
    # Sanitize URL for filename
    cam_name = source_url.rstrip("/").split("/")[-1]
    screenshot_path = str(config.DEBUG_DIR / f"{location_id}_{cam_name}_screenshot.png")

    ad_patterns = [
        "*doubleclick.net*", "*googlesyndication*", "*googleadservices*",
        "*adservice.google*", "*facebook.net/tr*", "*analytics*",
        "*adnxs.com*", "*adsrvr.org*", "*criteo*", "*pubmatic*",
        "*outbrain*", "*taboola*", "*amazon-adsystem*",
        "*popup*", "*popunder*", "*ad.plus*", "*adform*",
    ]

    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            context = browser.new_context(viewport={"width": 1280, "height": 960})
            page = context.new_page()

            # Block ads to keep the page stable
            page.route(
                "**/*",
                lambda route: route.abort()
                if any(pat.replace("*", "") in route.request.url for pat in ad_patterns)
                else route.continue_(),
            )

            # Prevent JS errors from missing ad SDK
            page.add_init_script('''
                window.googletag = window.googletag || {};
                googletag.cmd = googletag.cmd || [];
                googletag.pubads = () => ({
                    refresh(){}, enableSingleRequest(){}, setTargeting(){},
                    collapseEmptyDivs(){}, enableAsyncRendering(){},
                    disableInitialLoad(){}
                });
                googletag.display = () => {};
            ''')

            page.goto(source_url, wait_until="load", timeout=60000)

            # Cookie consent
            try:
                btn = page.get_by_role(
                    "button",
                    name=re.compile(r"(Accept all|Alle akzeptieren|Zustimmen)", re.IGNORECASE)
                )
                if btn.is_visible(timeout=5000.0):
                    btn.click()
                    btn.wait_for(state="hidden", timeout=5000.0)
                    time.sleep(2)
            except Exception:  # pylint: disable=broad-exception-caught
                pass

            # Click weather overlay using a robust selector
            time.sleep(2)
            try:
                # The button class is 'currentweatherdata'
                page.click("button.currentweatherdata", timeout=10000)
            except Exception:
                # Fallback to coordinate found by subagent
                page.mouse.click(156, 845)
            
            time.sleep(3) # Wait for overlay to animate and data to load

            page.screenshot(path=screenshot_path, full_page=False)

            browser.close()

        return {
            "raw_payload": screenshot_path,
            "fetched_at": now,
            "fetch_status": "success",
            "error_message": ""
        }
    except Exception as exc:  # pylint: disable=broad-exception-caught
        return {
            "fetched_at": now,
            "fetch_status": "failed",
            "error_message": str(exc)
        }


_CACHE = {}


def _get_reader() -> easyocr.Reader:
    """Lazily load the easyOCR reader."""
    if "reader" not in _CACHE:
        _CACHE["reader"] = easyocr.Reader(config.OCR_LANGUAGES)
    return _CACHE["reader"]


def parse_primary_source(state: WindGraphState) -> WindGraphState:
    """
    Parse the raw payload (screenshot) and extract observed wind values using OCR.
    """
    if state.get("fetch_status") != "success":
        return {"parse_status": "skipped", "error_message": "Fetch was not successful"}

    img_path = state.get("raw_payload", "")

    # Exract timestamp from URL if it matches archive format, else use fetched_at
    url = state.get("source_identifier", "")
    match = re.search(r"#/(\d{4})/(\d{2})/(\d{2})/(\d{2})(\d{2})", url)
    if match:
        observed_at = datetime(
            int(match.group(1)), int(match.group(2)), int(match.group(3)),
            int(match.group(4)), int(match.group(5)), tzinfo=timezone.utc
        ).isoformat()
    else:
        observed_at = state.get("fetched_at")

    try:
        img = cv2.imread(img_path)
        if img is None:
            return {
                "parse_status": "failed",
                "error_message": "Failed to read screenshot image"
            }

        reader = _get_reader()
        results = reader.readtext(img)
        full_text = " ".join(text for _, text, _ in results)

        wind_match = re.search(r"Wind:?\s*(\d+)\s*kts?", full_text, re.IGNORECASE)
        gust_match = re.search(r"B[öo]en:?\s*(\d+)\s*kts?", full_text, re.IGNORECASE)

        base_wind = float(wind_match.group(1)) if wind_match else 0.0
        gust = float(gust_match.group(1)) if gust_match else 0.0

        return {
            "parse_status": "success",
            "observed_at": observed_at,
            "base_wind_knots": base_wind,
            "gust_knots": gust,
            "error_message": ""
        }
    except Exception as exc:  # pylint: disable=broad-exception-caught
        return {
            "parse_status": "failed",
            "error_message": f"OCR extraction failed: {str(exc)}"
        }


def check_freshness(state: WindGraphState) -> WindGraphState:
    """
    Validate that the reading is recent enough.
    """
    if state.get("parse_status") != "success":
        return {"is_fresh": False, "error_message": "Parse was not successful"}

    observed_at_str = state.get("observed_at")
    limit_minutes = state.get("freshness_limit_minutes", 60)

    if not observed_at_str:
        return {"is_fresh": False, "error_message": "Missing observed_at"}

    try:
        observed_at = datetime.fromisoformat(observed_at_str)
        if observed_at.tzinfo is None:
            observed_at = observed_at.replace(tzinfo=timezone.utc)

        duration = datetime.now(timezone.utc) - observed_at
        minutes_old = duration.total_seconds() / 60.0

        is_fresh = 0 <= minutes_old <= limit_minutes
        return {
            "is_fresh": is_fresh
        }
    except ValueError as exc:
        return {
            "is_fresh": False,
            "error_message": f"Invalid observed_at format: {str(exc)}"
        }


def check_threshold(state: WindGraphState) -> WindGraphState:
    """
    Validate that base wind is strictly greater than the configured threshold.
    """
    if not state.get("is_fresh"):
        return {"threshold_exceeded": False}

    base_wind = state.get("base_wind_knots", 0.0)
    threshold = state.get("threshold_knots", 10.0)

    exceeded = base_wind > threshold
    return {
        "threshold_exceeded": exceeded
    }


def send_notification(state: WindGraphState) -> WindGraphState:
    """
    Trigger notification via Firebase Cloud Messaging if threshold exceeded.
    """
    if not state.get("threshold_exceeded"):
        return {"notification_sent": False}

    topic = state.get("target_fcm_topic", config.FCM_TOPIC)

    message = messaging.Message(
        data={
            'action': 'schedule_alarm',
            'base_wind': str(state.get("base_wind_knots")),
            'gust': str(state.get("gust_knots")),
        },
        topic=topic,
        android=messaging.AndroidConfig(priority='high'),
    )

    try:
        response = messaging.send(message)
        print(f"Successfully sent message to topic {topic}: {response}")
        return {"notification_sent": True}
    except Exception as exc:
        print(f"Error sending Firebase message: {exc}")
        return {"notification_sent": False, "error_message": f"Firebase send error: {str(exc)}"}


def save_to_firestore(state: WindGraphState) -> WindGraphState:
    """
    Save the parsed wind data to Firestore so the app can show realtime data.
    """
    if state.get("parse_status") != "success":
        return {"firestore_saved": False}

    try:
        db = firestore.client()
        
        source_url = state.get("source_identifier", "")
        # e.g., 'trimini', 'malcesinenord'
        cam_name = source_url.rstrip("/").split("/")[-1].lower()
        location_id = state.get("location_id", "default").lower()

        doc_ref = db.collection("latest_measurements").document(f"{location_id}_{cam_name}")
        doc_ref.set({
            "location_id": location_id,
            "cam_id": cam_name,
            "base_wind": state.get("base_wind_knots", 0.0),
            "gust": state.get("gust_knots", 0.0),
            "observed_at": state.get("observed_at"),
            "fetched_at": state.get("fetched_at"),
            "is_fresh": state.get("is_fresh", False),
            "updated_at": firestore.SERVER_TIMESTAMP
        })
        
        print(f"Saved live metrics to Firestore: {location_id}_{cam_name}")
        return {"firestore_saved": True}
    except Exception as exc:
        print(f"Error saving to Firestore: {exc}")
        return {"firestore_saved": False, "error_message": f"Firestore save error: {str(exc)}"}


def save_measurement(state: WindGraphState) -> WindGraphState:
    """
    Save the parsed measurement to the in-memory store for API access.
    """
    if state.get("parse_status") != "success":
        return {"measurement_saved": False}

    location_id = state.get("location_id", "default")
    try:
        store.set_measurement(location_id, dict(state))
        return {"measurement_saved": True}
    except Exception as exc:
        return {"measurement_saved": False, "error_message": f"Store save error: {str(exc)}"}
