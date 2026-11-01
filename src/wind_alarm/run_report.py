"""Per-station run status and the GitHub step summary.

A fresh station reading is `measured`. A timestamped reading that is too old
is `stale`. Anything else, including a garbled OCR fallback, is not a
measurement: the process exits non-zero instead of looking like 0 kt of calm wind.
"""

from __future__ import annotations

import os
from typing import Any

from wind_alarm.logger import get_logger

logger = get_logger("wind_alarm.report")

MEASURED = "measured"
STALE = "stale"
FETCH_FAILED = "fetch_failed"
OCR_UNCONFIRMED = "ocr_unconfirmed"


def station_status(result: Any) -> str:
    """Classify one webcam graph result. OCR never counts as measured."""
    if not hasattr(result, "get"):
        return FETCH_FAILED
    if result.get("fetch_status") == "failed":
        return FETCH_FAILED
    if result.get("parse_status") != "success":
        return FETCH_FAILED
    source = result.get("reading_source") or ""
    if source in {"ocr", "vision"}:
        return OCR_UNCONFIRMED
    if result.get("has_measurement_time", True) is False:
        return FETCH_FAILED
    if not result.get("is_fresh"):
        return STALE
    return MEASURED


def measurement_exit_code(statuses: list[str]) -> int:
    """0 when a fresh station reading exists. 1 when only stale. 2 when nothing was read."""
    if any(status == MEASURED for status in statuses):
        return 0
    if statuses and any(status == STALE for status in statuses):
        return 1
    return 2


def format_summary(location_id: str, threshold: float, webcams: dict, exit_code: int) -> str:
    lines = [
        f"## Wind alarm {location_id}",
        "",
        f"Threshold **> {threshold:g} kt**. Exit **{exit_code}** "
        "(0 fresh reading, 1 stale only, 2 no measurement).",
        "",
        "| Station | Status | Base kt | Gust kt | Observed (UTC) | Source | Error |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for cam_id, info in webcams.items():
        if not isinstance(info, dict):
            lines.append(f"| {cam_id} | {FETCH_FAILED} | | | | | |")
            continue
        lines.append(
            "| {cam} | {status} | {wind} | {gust} | {observed} | {source} | {error} |".format(
                cam=cam_id,
                status=info.get("status") or FETCH_FAILED,
                wind=_cell(info.get("base_wind")),
                gust=_cell(info.get("gust")),
                observed=info.get("observed_at") or "",
                source=info.get("reading_source") or "",
                error=(info.get("error_message") or "").replace("|", "/"),
            )
        )
    lines.append("")
    return "\n".join(lines)


def write_step_summary(text: str) -> None:
    """Print the summary and append it to $GITHUB_STEP_SUMMARY when Actions sets it."""
    print(text)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(text)
        if not text.endswith("\n"):
            handle.write("\n")


def _cell(value: Any) -> str:
    if value is None or value == "":
        return ""
    return str(value)
