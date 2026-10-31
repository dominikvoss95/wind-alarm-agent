"""Compare the station JSON with the overlay on the current frame.

The scheduled alarm trusts the station. This command is the independent check:
it reads the same frame a person sees and reports when OCR does not match any
recent station sample. It never sends a push.

Enable the daily GitHub run by setting the repository variable
WIND_READING_VERIFY to true. Without that variable the schedule is skipped.
`workflow_dispatch` and `python app.py --verify` always run.
"""

from __future__ import annotations

import json

from wind_alarm.config import config
from wind_alarm.logger import get_logger
from wind_alarm.nodes import _ocr_image
from wind_alarm.readings import (
    agrees_with_any_sample,
    parse_overlay_text,
    parse_station_payload,
    station_samples,
)
from wind_alarm.station_client import capture_webcam

logger = get_logger("wind_alarm.verify")


def verify_page(page_url: str, *, run_ocr: bool = True) -> dict:
    """Capture one webcam and compare station data with the overlay text."""
    spec = config.webcam_for_url(page_url)
    captured = capture_webcam(page_url)
    payload = json.loads(captured.station_json) if captured.station_json else None
    station = parse_station_payload(payload, captured.timezone)
    samples = station_samples(payload)
    ocr_text = ""
    overlay = None
    if run_ocr and captured.image_path:
        try:
            ocr_text = _ocr_image(captured.image_path)
            overlay = parse_overlay_text(ocr_text, captured.timezone)
        except Exception as exc:  # pylint: disable=broad-exception-caught
            logger.warning("overlay OCR failed for %s: %s", spec["slug"], exc)
            ocr_text = f"<ocr failed: {exc}>"

    if station.base_wind_knots is None:
        agree, detail = False, "; ".join(station.warnings) or "no station reading"
    elif overlay is None or overlay.base_wind_knots is None:
        agree, detail = False, "overlay could not be read"
    else:
        agree, detail = agrees_with_any_sample(samples, overlay)

    report = {
        "slug": spec["slug"],
        "page_url": page_url,
        "station_wind": station.base_wind_knots,
        "station_gust": station.gust_knots,
        "station_observed_at": station.observed_at.isoformat() if station.observed_at else "",
        "overlay_wind": None if overlay is None else overlay.base_wind_knots,
        "overlay_gust": None if overlay is None else overlay.gust_knots,
        "raw_ocr_text": ocr_text,
        "raw_station": station.raw_text,
        "agree": agree,
        "detail": detail,
    }
    logger.info(
        "verify %s agree=%s station=%s overlay=%s raw_ocr=%r detail=%s",
        spec["slug"],
        agree,
        station.base_wind_knots,
        None if overlay is None else overlay.base_wind_knots,
        ocr_text,
        detail,
    )
    return report


def verify_locations(location_ids: list[str] | None = None, *, run_ocr: bool = True) -> list[dict]:
    """Verify every webcam of the given locations. Defaults to both lakes."""
    chosen = location_ids or list(config.LOCATIONS)
    reports = []
    for location_id in chosen:
        location = config.LOCATIONS.get(location_id)
        if not location:
            raise ValueError(f"Unknown location: {location_id}")
        for url in location["urls"]:
            try:
                reports.append(verify_page(url, run_ocr=run_ocr))
            except Exception as exc:  # pylint: disable=broad-exception-caught
                logger.error("verify failed for %s: %s", url, exc)
                reports.append({
                    "slug": config.webcam_for_url(url)["slug"],
                    "page_url": url,
                    "agree": False,
                    "detail": str(exc),
                    "station_wind": None,
                    "overlay_wind": None,
                    "raw_ocr_text": "",
                })
    return reports


def exit_code(reports: list[dict]) -> int:
    """0 when every webcam matched. 1 when a reading disagreed or could not be fetched."""
    if reports and all(item.get("agree") for item in reports):
        return 0
    return 1
