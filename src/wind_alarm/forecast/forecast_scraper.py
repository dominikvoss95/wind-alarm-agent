"""
Scraper module using Playwright to capture screenshots of forecast sources.
"""
import logging
import os
import re
import time
from pathlib import Path
from typing import Dict
from playwright.sync_api import sync_playwright

from wind_alarm.config import config
from wind_alarm.forecast.forecast_sources import FORECAST_SOURCES

logger = logging.getLogger("wind_alarm.forecast_scraper")

def scrape_forecast_sources(location_id: str) -> Dict[str, str]:
    """
    Scrapes all configured forecast sources for a location.
    Returns a dictionary mapping source_id to the path of the captured screenshot.
    """
    sources = FORECAST_SOURCES.get(location_id)
    if not sources:
        logger.error("No forecast sources configured for location: %s", location_id)
        return {}

    # Define output directory in writeable /tmp or WRITE_ROOT
    forecast_dir = config.WRITE_ROOT / "forecast" / location_id
    forecast_dir.mkdir(parents=True, exist_ok=True)

    ad_patterns = [
        "*doubleclick.net*", "*googlesyndication*", "*googleadservices*",
        "*adservice.google*", "*facebook.net/tr*", "*analytics*",
        "*adnxs.com*", "*adsrvr.org*", "*criteo*", "*pubmatic*",
        "*outbrain*", "*taboola*", "*amazon-adsystem*",
        "*popup*", "*popunder*", "*ad.plus*", "*adform*",
    ]

    captured_screenshots = {}

    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(
                headless=True,
                args=["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage", "--single-process"]
            )
            # Use a slightly taller viewport to capture more content
            context = browser.new_context(viewport={"width": 1280, "height": 1280})
            
            for source in sources:
                source_id = source["id"]
                url = source["url"]
                name = source["name"]
                
                screenshot_path = str(forecast_dir / f"{source_id}.png")
                logger.info("Scraping forecast source: %s (%s)", name, url)
                
                try:
                    page = context.new_page()
                    
                    # Block ads to keep page layout clean and speed up load
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

                    # Navigate to source URL
                    page.goto(url, wait_until="load", timeout=45000)
                    time.sleep(3)  # Allow JS grids/charts to render
                    
                    # Handle cookie consent buttons
                    try:
                        btn = page.get_by_role(
                            "button",
                            name=re.compile(r"(Accept all|Alle akzeptieren|Zustimmen|I accept|Einverstanden|Zulassen)", re.IGNORECASE)
                        )
                        if btn.is_visible(timeout=3000.0):
                            btn.click()
                            time.sleep(2)
                    except Exception as exc:
                        logger.debug("No cookie consent button found/interacted for %s: %s", name, exc)
                    
                    # Custom scrolling or waiting for specific sites
                    if source_id == "foehn_diagram":
                        # The wwwind.com page has the Föhndiagramm lower down
                        page.evaluate("window.scrollTo(0, 400);")
                        time.sleep(2)
                    elif source_id == "windguru_arome":
                        # Windguru has an overlay or takes time to render tables
                        time.sleep(4)
                    
                    # Take screenshot of the viewport
                    page.screenshot(path=screenshot_path, full_page=False)
                    captured_screenshots[source_id] = screenshot_path
                    logger.info("Successfully scraped %s to %s", name, screenshot_path)
                    
                except Exception as exc:
                    logger.error("Failed to scrape forecast source %s: %s", name, exc)
                finally:
                    page.close()
                    
            browser.close()
            
    except Exception as exc:
        logger.error("Global Playwright error during forecast scraping: %s", exc)

    return captured_screenshots
