"""Read the addicted-sports station JSON and the current 640px frame.

The page draws "Wind" and "Böen" from getWeatherData.php (fields wsavg and
wsmax, knots). The same numbers are burned into current/640.jpg, which is the
frame the live page shows. Downloading that frame avoids a full-page screenshot
that also contains other webcams, the forecast, and the clock.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx

from wind_alarm.config import config
from wind_alarm.logger import get_logger

logger = get_logger("wind_alarm.station")

_CSRF_RE = re.compile(r'name="csrf-token"\s+content="([^"]+)"')
_NAME_RE = re.compile(r"webcam\.name\s*=\s*'([^']+)'")
_IMAGE_SLOT_RE = re.compile(r"(\d{4}/\d{2}/\d{2}/\d{4})")


@dataclass
class WebcamCapture:
    page_url: str
    cam_slug: str
    wc_name: str
    timezone: str
    station_json: str
    image_path: str
    fetched_at: str


def capture_webcam(page_url: str, dest_dir: Path | None = None) -> WebcamCapture:
    """Fetch station JSON and the current overlay image for one webcam page."""
    spec = config.webcam_for_url(page_url)
    dest = dest_dir or config.DEBUG_DIR
    dest.mkdir(parents=True, exist_ok=True)
    fetched_at = datetime.now(timezone.utc).isoformat()

    headers = {
        "User-Agent": "wind-alarm-agent/1.0",
        "Accept": "text/html,application/json,image/jpeg",
    }
    with httpx.Client(headers=headers, timeout=30.0, follow_redirects=True) as client:
        wc_name, token = _page_identity(client, page_url, spec)
        station = _load_station(client, page_url, wc_name, token, spec["timezone"])
        image_path = _download_image(client, spec, dest)

    if not station and not image_path:
        image_path = _playwright_image(page_url, dest, spec["slug"])
    if not station and not image_path:
        raise RuntimeError(f"no station data and no image for {page_url}")

    station_text = json.dumps(station) if station else ""
    if station_text:
        (dest / f"{spec['slug']}_station.json").write_text(station_text, encoding="utf-8")
    logger.info(
        "captured %s wc=%s station=%s image=%s",
        spec["slug"],
        wc_name,
        bool(station_text),
        image_path or "-",
    )
    return WebcamCapture(
        page_url=page_url,
        cam_slug=spec["slug"],
        wc_name=wc_name,
        timezone=spec["timezone"],
        station_json=station_text,
        image_path=image_path,
        fetched_at=fetched_at,
    )


def _page_identity(client: httpx.Client, page_url: str, spec: dict) -> tuple[str, str]:
    response = client.get(page_url)
    response.raise_for_status()
    html = response.text
    token_match = _CSRF_RE.search(html)
    name_match = _NAME_RE.search(html)
    token = token_match.group(1) if token_match else ""
    wc_name = name_match.group(1) if name_match else spec["wc"]
    return wc_name, token


def _load_station(
    client: httpx.Client,
    page_url: str,
    wc_name: str,
    token: str,
    tz_name: str,
) -> dict | None:
    stop = _slot_from_url(page_url) or _current_image_slot(client, page_url, wc_name, token, tz_name)
    start = _shift_slot(stop, -30)
    url = (
        "https://www.addicted-sports.com/fileadmin/webcam/src/getWeatherData.php"
        f"?startimg={start}&stopimg={stop}&wc={wc_name}"
    )
    payload = _get_json(client, url, page_url, token)
    if _csrf_rejected(payload) and token:
        _, token = _page_identity(client, page_url, {"wc": wc_name})
        payload = _get_json(client, url, page_url, token)
    if not isinstance(payload, dict) or _csrf_rejected(payload):
        logger.warning("station JSON unavailable for %s", wc_name)
        return None
    if not (payload.get("measurment") or payload.get("measurement")):
        logger.warning("station JSON for %s has no measurements", wc_name)
        return None
    return payload


def _current_image_slot(
    client: httpx.Client,
    page_url: str,
    wc_name: str,
    token: str,
    tz_name: str,
) -> str:
    url = (
        "https://www.addicted-sports.com/fileadmin/webcam/v14include/list.php"
        f"?img=&wc={wc_name}&thumbs=0"
    )
    payload = _get_json(client, url, page_url, token)
    image = ""
    if isinstance(payload, dict):
        image = str(payload.get("image") or "")
    match = _IMAGE_SLOT_RE.search(image)
    if match:
        return match.group(1)
    now = datetime.now(_zone(tz_name))
    return f"{now.year:04d}/{now.month:02d}/{now.day:02d}/{now.hour:02d}{now.minute:02d}"


def _download_image(client: httpx.Client, spec: dict, dest: Path) -> str:
    stamp = int(datetime.now(timezone.utc).timestamp())
    url = spec["image_url"]
    separator = "&" if "?" in url else "?"
    try:
        response = client.get(f"{url}{separator}{stamp}")
        response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.warning("image download failed for %s: %s", spec["slug"], exc)
        return ""
    if "image" not in response.headers.get("content-type", "") and not response.content.startswith(b"\xff\xd8"):
        logger.warning("image response for %s was not a JPEG", spec["slug"])
        return ""
    path = dest / f"{spec['slug']}_640.jpg"
    path.write_bytes(response.content)
    return str(path)


def _get_json(client: httpx.Client, url: str, page_url: str, token: str) -> dict | None:
    headers = {"Referer": page_url, "X-Requested-With": "XMLHttpRequest"}
    if token:
        headers["CsrfToken"] = token
    try:
        response = client.get(url, headers=headers)
        response.raise_for_status()
        return response.json()
    except (httpx.HTTPError, json.JSONDecodeError) as exc:
        logger.warning("request failed %s: %s", url, exc)
        return None


def _csrf_rejected(payload: dict | None) -> bool:
    if not isinstance(payload, dict):
        return False
    return payload.get("status") in {"Wrong CSRF token.", "No CSRF token."}


def _slot_from_url(page_url: str) -> str | None:
    match = re.search(r"#/(\d{4})/(\d{2})/(\d{2})/(\d{4})", page_url or "")
    if not match:
        return None
    return f"{match.group(1)}/{match.group(2)}/{match.group(3)}/{match.group(4)}"


def _shift_slot(slot: str, minutes: int) -> str:
    year, month, day, hm = slot.split("/")
    moment = datetime(int(year), int(month), int(day), int(hm[:2]), int(hm[2:]))
    moment += timedelta(minutes=minutes)
    return f"{moment.year:04d}/{moment.month:02d}/{moment.day:02d}/{moment.hour:02d}{moment.minute:02d}"


def _zone(tz_name: str):
    from zoneinfo import ZoneInfo
    return ZoneInfo(tz_name)


def _playwright_image(page_url: str, dest: Path, slug: str) -> str:
    """Last resort: screenshot the webcam image element, not the whole page."""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        logger.warning("playwright is not installed; cannot capture %s", page_url)
        return ""

    path = dest / f"{slug}_640.jpg"
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(
                headless=True,
                args=["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"],
            )
            page = browser.new_page(viewport={"width": 1280, "height": 960})
            page.goto(page_url, wait_until="load", timeout=60000)
            image = page.locator("img.wcmin, img[id^='img']").first
            image.wait_for(state="visible", timeout=20000)
            image.screenshot(path=str(path))
            browser.close()
    except Exception as exc:  # pylint: disable=broad-exception-caught
        logger.warning("playwright image capture failed for %s: %s", page_url, exc)
        return ""
    return str(path)
