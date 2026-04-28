"""
Webcam history fetcher — captures daily screenshots from the
Addicted Sports archive and saves them as training data.

Uses Playwright for browser automation with built-in ad blocking
and cookie consent handling.
"""

import asyncio
import re
from datetime import datetime, timedelta
from pathlib import Path
from typing import AsyncIterator, Dict

from playwright.async_api import async_playwright, BrowserContext, Page

from wind_alarm.config import config
from wind_alarm.logger import get_logger

logger = get_logger("wind_alarm.fetcher")

# ── config ───────────────────────────────────────────────────────────
CAM_ID = config.get("webcam.cam_id")
PAGE_URL_TEMPLATE = config.get("webcam.page_url_template")
SAVE_DIR = Path(config.get("paths.raw_image_dir"))
YEARS_BACK = config.get("webcam.years_back", 5)
DAILY_AT = config.get("webcam.daily_at")

# domains silently blocked to keep the page stable
_AD_PATTERNS = [
    "*doubleclick.net*", "*googlesyndication*", "*googleadservices*",
    "*adservice.google*", "*facebook.net/tr*", "*analytics*",
    "*adnxs.com*", "*adsrvr.org*", "*criteo*", "*pubmatic*",
    "*outbrain*", "*taboola*", "*amazon-adsystem*",
    "*popup*", "*popunder*", "*ad.plus*", "*adform*",
]


def _img_path(dt: datetime, suffix: str = "wide") -> Path:
    prefix = "full_page" if suffix == "wide" else "zoom_water"
    return SAVE_DIR / f"{prefix}_{dt.strftime('%Y-%m-%d_%H-%M')}.png"


def _url_for(dt: datetime) -> str:
    return PAGE_URL_TEMPLATE.format(
        cam_id=CAM_ID,
        y=dt.strftime("%Y"),
        m=dt.strftime("%m"),
        d=dt.strftime("%d"),
        hm=dt.strftime("%H%M"),
    )


async def daterange_backward() -> AsyncIterator[datetime]:
    """Yield timestamps going backwards from today."""
    now = datetime.now()
    end = now - timedelta(days=YEARS_BACK * 365)

    if DAILY_AT:
        h, m = map(int, DAILY_AT.split(":"))
        cur = now.replace(hour=h, minute=m, second=0, microsecond=0)
        if cur > now:
            cur -= timedelta(days=1)
        while cur > end:
            yield cur
            cur -= timedelta(days=1)
    else:
        interval = config.get("webcam.interval_minutes", 30)
        cur = now
        while cur > end:
            yield cur
            cur -= timedelta(minutes=interval)


# ── browser helpers ──────────────────────────────────────────────────

async def _inject_marker(page: Page, x: int, y: int, timeout_ms: int = 2000):
    """Drop a small red dot on the page for visual debugging."""
    try:
        await page.evaluate(f"""
        () => {{
            const old = document.getElementById("click-marker");
            if (old) old.remove();
            const d = document.createElement("div");
            d.id = "click-marker";
            Object.assign(d.style, {{
                position:"fixed", left:"{x-7}px", top:"{y-7}px",
                width:"14px", height:"14px", background:"rgba(255,0,0,.8)",
                border:"2px solid #fff", borderRadius:"50%",
                zIndex:"2147483647", pointerEvents:"none"
            }});
            document.body.appendChild(d);
            {"" if timeout_ms == 0 else f'setTimeout(()=>d.remove(),{timeout_ms});'}
        }}
        """)
    except Exception as exc:
        logger.debug("marker inject failed: %s", exc)


async def _click_weather_overlay(page: Page):
    """Click the weather cloud icon to reveal wind data."""
    # The icon is at 198, 640 in standard viewport
    # We add a small sleep to ensure page is settled
    await asyncio.sleep(2)
    await _inject_marker(page, 198, 640)
    await page.mouse.click(198, 640)
    await asyncio.sleep(2)
    logger.debug("Weather overlay toggled")


async def setup_session(context: BrowserContext, start_dt: datetime) -> Page:
    """Open the page, dismiss cookie banner, activate weather overlay."""
    page = await context.new_page()

    # block ads so overlays stay clickable
    await page.route(
        "**/*",
        lambda route: route.abort()
        if any(p.replace("*", "") in route.request.url for p in _AD_PATTERNS)
        else route.continue_(),
    )

    # prevent JS errors from missing ad SDK
    await page.add_init_script("""
        window.googletag = window.googletag || {};
        googletag.cmd = googletag.cmd || [];
        googletag.pubads = () => ({
            refresh(){}, enableSingleRequest(){}, setTargeting(){},
            collapseEmptyDivs(){}, enableAsyncRendering(){},
            disableInitialLoad(){}
        });
        googletag.display = () => {};
    """)

    url = _url_for(start_dt)
    logger.info("Opening session at %s", url)
    
    # Retry goto in case of network hiccup
    for attempt in range(3):
        try:
            await page.goto(url, wait_until="load", timeout=60_000)
            break
        except Exception:
            if attempt == 2: raise
            logger.warning("Goto failed, retrying...")
            await asyncio.sleep(5)

    # cookie consent
    try:
        btn = page.get_by_role(
            "button",
            name=re.compile(r"(Accept all|Alle akzeptieren|Zustimmen)", re.IGNORECASE),
        )
        if await btn.is_visible(timeout=5000):
            await btn.click()
            await btn.wait_for(state="hidden", timeout=5000)
            await asyncio.sleep(2)
    except Exception:
        pass

    await _click_weather_overlay(page)
    await asyncio.sleep(2)
    return page


async def capture_history_point(
    dt: datetime, page: Page, *, is_initial: bool = False
) -> str:
    """Navigate to *dt* and save wide + zoom screenshots. Returns status string."""
    wide_out = _img_path(dt, "wide")
    zoom_out = _img_path(dt, "zoom")

    if wide_out.exists() and zoom_out.exists():
        return "skip"

    try:
        if not is_initial:
            await page.goto(_url_for(dt), wait_until="load")
            await page.reload(wait_until="load")
            await asyncio.sleep(2)

        logger.info("Capturing %s (wide + zoom)", dt.strftime("%Y-%m-%d %H:%M"))
        
        # 1. Wide Screenshot (with wind data)
        wide_out.parent.mkdir(parents=True, exist_ok=True)
        await page.screenshot(path=str(wide_out), full_page=False)

        # 2. Zoom Detail (Click image and scroll)
        await _inject_marker(page, 640, 600)
        await page.mouse.click(640, 600)
        await asyncio.sleep(1)
        
        # Scroll down a bit to center the water surface in the zoomed view
        await page.mouse.wheel(0, 200)
        await asyncio.sleep(2) # wait for zoom and scroll animation
        
        await page.screenshot(path=str(zoom_out), full_page=False)
        
        return "ok"

    except Exception as exc:
        logger.error("Capture failed at %s: %s", dt, exc)
        return "err"


# ── main loop ────────────────────────────────────────────────────────

async def run_fetch():
    logger.info("Starting collection [cam=%s]", CAM_ID)

    stats: Dict[str, int] = {"ok": 0, "skip": 0, "err": 0}
    queue = [dt async for dt in daterange_backward()]

    async with async_playwright() as pw:
        # Launching with a bit more stability settings
        browser = await pw.chromium.launch(headless=True)
        ctx = await browser.new_context(
            viewport={"width": 1280, "height": 960},
            device_scale_factor=1,
        )

        try:
            if not queue:
                logger.warning("Empty date range.")
                return

            # Robust session setup with retries
            page = None
            for attempt in range(3):
                try:
                    page = await setup_session(ctx, queue[0])
                    break
                except Exception as e:
                    logger.error("Session setup attempt %d failed: %s", attempt + 1, e)
                    if attempt == 2: raise
                    await asyncio.sleep(10)

            for i, dt in enumerate(queue):
                # if browser crashed or page is broken, we'd ideally recreate it here
                # but for now, we just proceed
                status = await capture_history_point(dt, page, is_initial=(i == 0))
                stats[status] += 1

                if stats["ok"] and stats["ok"] % 5 == 0 and status == "ok":
                    logger.info(
                        "Progress: ok=%d  skip=%d  err=%d",
                        stats["ok"], stats["skip"], stats["err"],
                    )
        finally:
            await browser.close()

    logger.info("Done. %s", stats)


if __name__ == "__main__":
    try:
        asyncio.run(run_fetch())
    except KeyboardInterrupt:
        logger.warning("Aborted by user.")
