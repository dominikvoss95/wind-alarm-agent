"""
Node definitions for the Wind Alarm graph.
"""
import json
import logging
import re

from firebase_admin import messaging

from wind_alarm.config import config
from wind_alarm.logger import get_logger
from wind_alarm.notify import build_alarm_message
from wind_alarm.readings import (
    crop_overlay,
    observed_from_page_url,
    parse_overlay_text,
    parse_station_payload,
    parse_vision_payload,
)
from wind_alarm.state import WindGraphState
from wind_alarm.station_client import capture_webcam

logger = get_logger("wind_alarm.nodes")

_VISION_PROMPT = (
    "Read the wind overlay in the bottom-left of this webcam image. "
    "The line with °C is air temperature, not wind. "
    "The clock (HH:MM) and the date (DD.MM.YYYY) are not wind. "
    "Base wind is the knots value next to the wind flag. It often has no word in front of it, "
    "for example '4 kts' or '2.17 kts'. "
    "Gust is the line that starts with Böe or Böen, for example 'Böe 7.56 kts'. "
    "Return only JSON with keys wind, gust, temperature_c, local_time. "
    "wind and gust are numbers in knots with the decimals you see. Do not round. "
    "local_time is YYYY-MM-DDTHH:MM from the overlay clock in local time. "
    "Never put the temperature or the hour into wind."
)


def fetch_primary_source(state: WindGraphState) -> WindGraphState:
    """Load station JSON and the current 640px frame for this webcam."""
    source_url = state.get("source_identifier")
    if not source_url:
        return {
            "fetch_status": "failed",
            "error_message": "Missing source_identifier",
        }

    try:
        captured = capture_webcam(source_url)
    except Exception as exc:  # pylint: disable=broad-exception-caught
        logger.error("fetch failed for %s: %s", source_url, exc)
        return {
            "fetch_status": "failed",
            "error_message": str(exc),
        }

    return {
        "raw_payload": captured.image_path,
        "station_json": captured.station_json,
        "cam_timezone": captured.timezone,
        "fetched_at": captured.fetched_at,
        "fetch_status": "success",
        "error_message": "",
    }


_CACHE = {}


def _get_reader():
    """Lazily load the easyOCR reader."""
    import easyocr
    if "reader" not in _CACHE:
        _CACHE["reader"] = easyocr.Reader(["en", "de"])
    return _CACHE["reader"]


def _ocr_image(img_path: str) -> str:
    import cv2
    img = cv2.imread(img_path)
    if img is None:
        raise FileNotFoundError(f"Failed to read screenshot image: {img_path}")
    crop = crop_overlay(img)
    try:
        height, width = crop.shape[:2]
        if int(height) < 400 and int(width) > 0:
            crop = cv2.resize(crop, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC)
    except (TypeError, ValueError, AttributeError, cv2.error):
        pass
    results = _get_reader().readtext(crop)
    return " ".join(text for _, text, _ in results)


def _vision_reading(img_path: str, tz_name: str, backend: str):
    raw = _ask_vision(img_path, backend)
    logger.info("vision raw response (%s): %s", backend, raw)
    match = re.search(r"\{.*\}", raw, re.DOTALL)
    if not match:
        raise ValueError(f"Could not parse JSON from {backend} response: {raw}")
    return parse_vision_payload(json.loads(match.group(0)), tz_name)


def _ask_vision(img_path: str, backend: str) -> str:
    if backend == "azure":
        return _ask_azure(img_path)
    return _ask_bedrock(img_path)


def _ask_azure(img_path: str) -> str:
    import base64
    from openai import AzureOpenAI
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider

    endpoint = config.AZURE_OPENAI_ENDPOINT
    key = config.AZURE_OPENAI_KEY
    deployment = config.AZURE_OPENAI_DEPLOYMENT_NAME
    if key:
        client = AzureOpenAI(
            azure_endpoint=endpoint,
            api_key=key,
            api_version="2024-08-01-preview",
        )
    else:
        token_provider = get_bearer_token_provider(
            DefaultAzureCredential(),
            "https://cognitiveservices.azure.com/.default",
        )
        client = AzureOpenAI(
            azure_endpoint=endpoint,
            azure_ad_token_provider=token_provider,
            api_version="2024-08-01-preview",
        )
    with open(img_path, "rb") as handle:
        image_bytes = handle.read()
    encoded = base64.b64encode(image_bytes).decode("utf-8")
    response = client.chat.completions.create(
        model=deployment,
        messages=[{
            "role": "user",
            "content": [
                {"type": "text", "text": _VISION_PROMPT},
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{encoded}"}},
            ],
        }],
        response_format={"type": "json_object"},
        temperature=0.0,
    )
    return response.choices[0].message.content or ""


def _ask_bedrock(img_path: str) -> str:
    import os
    import boto3

    bedrock_region = os.environ.get("BEDROCK_REGION", "us-east-1")
    client = boto3.client("bedrock-runtime", region_name=bedrock_region)
    with open(img_path, "rb") as handle:
        image_bytes = handle.read()
    messages = [{
        "role": "user",
        "content": [
            {"text": _VISION_PROMPT},
            {"image": {"format": "png", "source": {"bytes": image_bytes}}},
        ],
    }]
    model_id = os.environ.get("BEDROCK_OCR_MODEL_ID", "amazon.nova-lite-v1:0")
    response = client.converse(
        modelId=model_id,
        messages=messages,
        inferenceConfig={"maxTokens": 200, "temperature": 0.0},
    )
    return response["output"]["message"]["content"][0]["text"]


def _timezone_for(state: WindGraphState) -> str:
    if state.get("cam_timezone"):
        return state["cam_timezone"]
    return config.webcam_for_url(state.get("source_identifier", "")).get("timezone", "Europe/Berlin")


def parse_primary_source(state: WindGraphState) -> WindGraphState:
    """Prefer the station JSON. Fall back to overlay OCR, then a vision model."""
    if state.get("fetch_status") != "success":
        return {"parse_status": "skipped"}

    tz_name = _timezone_for(state)
    img_path = state.get("raw_payload", "")
    station_reading = None
    raw_station = state.get("station_json") or ""
    if raw_station:
        try:
            station_reading = parse_station_payload(json.loads(raw_station), tz_name)
        except json.JSONDecodeError as exc:
            logger.warning("station JSON was not valid: %s", exc)
            station_reading = None

    ocr_text = ""
    ocr_reading = None
    need_fallback = station_reading is None or station_reading.base_wind_knots is None
    if need_fallback and img_path and not config.USE_AZURE and not config.USE_AWS:
        try:
            ocr_text = _ocr_image(img_path)
            ocr_reading = parse_overlay_text(ocr_text, tz_name)
            logger.info("ocr raw=%r parsed wind=%s gust=%s warnings=%s",
                        ocr_text, ocr_reading.base_wind_knots, ocr_reading.gust_knots, ocr_reading.warnings)
        except FileNotFoundError as exc:
            return {"parse_status": "failed", "error_message": str(exc)}
        except Exception as exc:  # pylint: disable=broad-exception-caught
            logger.warning("OCR failed: %s", exc)
            ocr_reading = None

    vision_reading = None
    if need_fallback and (ocr_reading is None or ocr_reading.base_wind_knots is None):
        if config.USE_AZURE or config.USE_AWS:
            backend = "azure" if config.USE_AZURE else "bedrock"
            try:
                vision_reading = _vision_reading(img_path, tz_name, backend)
                logger.info(
                    "vision parsed wind=%s gust=%s warnings=%s",
                    vision_reading.base_wind_knots,
                    vision_reading.gust_knots,
                    vision_reading.warnings,
                )
            except Exception as exc:  # pylint: disable=broad-exception-caught
                return {
                    "parse_status": "failed",
                    "error_message": f"{backend} OCR extraction failed: {exc}",
                }

    chosen = _choose_reading(station_reading, ocr_reading, vision_reading)
    if chosen is None or chosen.base_wind_knots is None:
        detail = ""
        for item in (station_reading, ocr_reading, vision_reading):
            if item and item.warnings:
                detail = "; ".join(item.warnings)
                break
        if not detail:
            detail = "Wind speed not found in OCR text"
        return {
            "parse_status": "failed",
            "raw_ocr_text": ocr_text,
            "error_message": detail,
        }

    if chosen.observed_at is None:
        chosen.observed_at = observed_from_page_url(state.get("source_identifier", ""), tz_name)

    logger.info(
        "parsed source=%s wind=%s gust=%s observed=%s raw_station=%r raw_ocr=%r",
        chosen.source,
        chosen.base_wind_knots,
        chosen.gust_knots,
        chosen.observed_at.isoformat() if chosen.observed_at else "",
        station_reading.raw_text if station_reading else "",
        ocr_text,
    )
    fields = chosen.as_state()
    fields["parse_status"] = "success"
    fields["error_message"] = ""
    if not fields.get("observed_at"):
        fields["observed_at"] = state.get("fetched_at") or ""
        fields["has_measurement_time"] = False
    return fields


def _choose_reading(station, ocr, vision):
    if station is not None and station.base_wind_knots is not None and not _hard_warning(station):
        return station
    if ocr is not None and ocr.base_wind_knots is not None and not ocr.warnings:
        return ocr
    if vision is not None and vision.base_wind_knots is not None and not vision.warnings:
        return vision
    return None


def _hard_warning(reading) -> bool:
    """Station timestamps can be missing only when the payload is unusable."""
    return any("outside the plausible" in note or "unreadable" in note for note in reading.warnings)


def check_freshness(state: WindGraphState) -> WindGraphState:
    """Validate that the measurement itself (not the fetch time) is recent enough."""
    if state.get("parse_status") != "success":
        return {"is_fresh": False}

    if state.get("has_measurement_time") is False:
        return {"is_fresh": False, "error_message": "No measurement timestamp"}

    observed_at_str = state.get("observed_at")
    limit_minutes = state.get("freshness_limit_minutes", 60)
    if not observed_at_str:
        return {"is_fresh": False, "error_message": "Missing observed_at"}

    try:
        from datetime import datetime, timezone
        observed_at = datetime.fromisoformat(observed_at_str)
        if observed_at.tzinfo is None:
            observed_at = observed_at.replace(tzinfo=timezone.utc)

        duration = datetime.now(timezone.utc) - observed_at
        minutes_old = duration.total_seconds() / 60.0
        # Two minutes of future skew covers clock error. A timezone treated as UTC
        # is about 60 minutes in the future and stays stale.
        is_fresh = -2 <= minutes_old <= limit_minutes
        return {"is_fresh": is_fresh}
    except ValueError as exc:
        return {
            "is_fresh": False,
            "error_message": f"Invalid observed_at format: {exc}",
        }


def check_threshold(state: WindGraphState) -> WindGraphState:
    """Validate that base wind is strictly greater than the configured threshold."""
    if not state.get("is_fresh"):
        return {"threshold_exceeded": False}

    base_wind = state.get("base_wind_knots", 0.0)
    threshold = state.get("threshold_knots", 10.0)
    return {"threshold_exceeded": base_wind > threshold}


def send_notification(state: WindGraphState) -> WindGraphState:
    """Trigger notification only when all required conditions are met."""
    if state.get("skip_notification") or not state.get("threshold_exceeded"):
        return {"notification_sent": False}

    topic = state.get("target_fcm_topic") or config.FCM_TOPIC
    base_wind = state.get("base_wind_knots", 0.0)
    location_id = state.get("location_id", "default")
    message = build_alarm_message(
        topic=topic,
        title="Wind Alarm!",
        body=f"Wind at {location_id} is {base_wind} kts.",
        location_id=location_id,
        wind_knots=base_wind,
    )

    try:
        config.initialize_firebase()
        response = messaging.send(message)
        logging.info("Successfully sent message: %s", response)
        return {"notification_sent": True}
    except Exception as exc:  # pylint: disable=broad-exception-caught
        logging.error("Failed to send FCM notification: %s", exc)
        return {"notification_sent": False, "error_message": str(exc)}
