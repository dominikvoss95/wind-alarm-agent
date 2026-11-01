"""Parse addicted-sports wind readings from station JSON or overlay text.

The live JPEG overlay (bottom left of the 640px frame) looks like this:

    SA, 19:00
    31.10.2026
    16°C
    4 kts
    Böe 7.56 kts

Base wind has no "Wind" label. Gust is "Böe" (not "Böen") and may be a decimal.
The clock and the °C line are not wind. The "Wind & Wetter" panel still uses
the older "Wind" / "Böen" labels with values rounded from the same station.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

# These lakes do not produce hurricane-force readings. Anything above this
# is a misread (a year, a clock, a pressure) rather than a real wind.
MAX_PLAUSIBLE_KNOTS = 75.0

# OCR of the burned-in frame can lag the newest station minute by about one
# minute, and the panel rounds. Verification treats a gap inside this band
# as the same reading.
STATION_OCR_TOLERANCE_KNOTS = 2.0

_GUST_RE = re.compile(
    r"B[öo]e[n]?\s*:?\s*(\d+(?:[.,]\d+)?)\s*kts?\b",
    re.IGNORECASE,
)
_LABELED_WIND_RE = re.compile(
    r"(?<![A-Za-zÄÖÜäöü])Wind\s*:?\s*(\d+(?:[.,]\d+)?)\s*kts?\b",
    re.IGNORECASE,
)
_KTS_RE = re.compile(r"(\d+(?:[.,]\d+)?)\s*kts?\b", re.IGNORECASE)
_OTHER_UNIT_RE = re.compile(
    r"(\d+(?:[.,]\d+)?)\s*(km/h|kmh|m/s|mph)\b",
    re.IGNORECASE,
)
_TEMP_RE = re.compile(
    r"(\d+(?:[.,]\d+)?)\s*(?:°|º|˚)\s*C\b",
    re.IGNORECASE,
)
_DATE_RE = re.compile(r"\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b")
_TIME_RE = re.compile(r"\b(\d{1,2}):(\d{2})\b")
_HASH_RE = re.compile(r"#/(\d{4})/(\d{2})/(\d{2})/(\d{2})(\d{2})")


@dataclass
class WindReading:
    """One parsed measurement. Knots stay as floats, including decimals."""

    base_wind_knots: float | None = None
    gust_knots: float | None = None
    temperature_c: float | None = None
    observed_at: datetime | None = None
    source: str = ""
    raw_text: str = ""
    warnings: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return self.base_wind_knots is not None and not self.warnings

    def as_state(self) -> dict[str, Any]:
        observed = ""
        if self.observed_at is not None:
            observed = self.observed_at.astimezone(timezone.utc).isoformat()
        return {
            "base_wind_knots": self.base_wind_knots,
            "gust_knots": self.gust_knots if self.gust_knots is not None else 0.0,
            "observed_at": observed,
            "temperature_c": self.temperature_c,
            "reading_source": self.source,
            "raw_ocr_text": self.raw_text,
            "has_measurement_time": self.observed_at is not None,
        }


def _number(raw: str) -> float:
    return float(raw.replace(",", "."))


def crop_overlay(img):
    """Bottom-left overlay of a webcam frame. Returns the image unchanged when it has no shape."""
    try:
        height, width = img.shape[:2]
        height = int(height)
        width = int(width)
    except (TypeError, ValueError, AttributeError):
        return img
    if height < 20 or width < 20:
        return img
    top = int(height * 0.60)
    right = max(int(width * 0.38), 1)
    return img[top:height, 0:right]


def parse_overlay_text(raw_text: str, tz_name: str = "Europe/Berlin") -> WindReading:
    """Parse overlay or panel text. Rejects temperature, clock, and non-knot units."""
    reading = WindReading(source="ocr", raw_text=raw_text or "")
    text = raw_text or ""
    if not text.strip():
        reading.warnings.append("Wind speed not found in OCR text")
        return reading

    other_units = _OTHER_UNIT_RE.findall(text)
    if other_units and not _KTS_RE.search(text):
        unit = other_units[0][1]
        reading.warnings.append(f"unsupported wind unit {unit}; expected kts")
        return reading

    temp_match = _TEMP_RE.search(text)
    if temp_match:
        reading.temperature_c = _number(temp_match.group(1))

    gust_match = _GUST_RE.search(text)
    gust_value = _number(gust_match.group(1)) if gust_match else None
    labeled = _LABELED_WIND_RE.search(text)
    knot_values = [_number(match.group(1)) for match in _KTS_RE.finditer(text)]

    base = _number(labeled.group(1)) if labeled else None
    if base is None:
        candidates = []
        for value in knot_values:
            if gust_value is not None and abs(value - gust_value) < 0.05:
                continue
            candidates.append(value)
        unique = []
        for value in candidates:
            if not any(abs(value - seen) < 0.05 for seen in unique):
                unique.append(value)
        if len(unique) == 1:
            base = unique[0]
        elif len(unique) > 1:
            reading.warnings.append(
                "ambiguous wind values in OCR text: " + ", ".join(str(v) for v in unique)
            )
            return reading

    if base is None:
        reading.warnings.append("Wind speed not found in OCR text")
        return reading

    if not _plausible(base) or (gust_value is not None and not _plausible(gust_value)):
        reading.warnings.append(f"wind {base} kts is outside the plausible range")
        return reading

    if _looks_like_temperature(base, reading.temperature_c, gust_value):
        reading.warnings.append(
            f"rejected wind {base} because it matches the temperature, not the knots line"
        )
        return reading

    hour = _clock_hour(text)
    if hour is not None and abs(base - hour) < 0.05 and gust_value is not None and base > gust_value + 1:
        reading.warnings.append(f"rejected wind {base} because it matches the clock hour")
        return reading

    reading.base_wind_knots = base
    reading.gust_knots = gust_value
    reading.observed_at = _overlay_timestamp(text, tz_name)
    return reading


def parse_station_payload(payload: dict | None, tz_name: str = "Europe/Berlin") -> WindReading:
    """Use the newest sample from getWeatherData.php. wsavg/wsmax are knots."""
    reading = WindReading(source="station")
    if not isinstance(payload, dict):
        reading.warnings.append("station payload missing")
        return reading
    if payload.get("status") in {"Wrong CSRF token.", "No CSRF token."}:
        reading.warnings.append(f"station request rejected: {payload.get('status')}")
        return reading

    samples = payload.get("measurment") or payload.get("measurement") or {}
    if not isinstance(samples, dict) or not samples:
        reading.warnings.append("station payload has no measurements")
        return reading

    latest = max(samples.values(), key=_sample_stamp)
    try:
        base = float(latest["wsavg"])
        gust = float(latest["wsmax"]) if latest.get("wsmax") not in (None, "") else None
    except (KeyError, TypeError, ValueError) as exc:
        reading.warnings.append(f"station wind values unreadable: {exc}")
        return reading

    if not _plausible(base) or (gust is not None and not _plausible(gust)):
        reading.warnings.append(f"station wind {base} kts is outside the plausible range")
        return reading

    stamp = _sample_stamp(latest)
    observed = datetime.fromtimestamp(stamp, tz=timezone.utc) if stamp else None
    if observed is None:
        observed = _parse_local_datetime(str(latest.get("tsdatetime") or ""), tz_name)

    temp_raw = latest.get("temp")
    try:
        temperature = float(temp_raw) if temp_raw not in (None, "") else None
    except (TypeError, ValueError):
        temperature = None

    reading.base_wind_knots = base
    reading.gust_knots = gust
    reading.temperature_c = temperature
    reading.observed_at = observed
    reading.raw_text = (
        f"wsavg={base} wsmax={gust} temp={temperature} "
        f"tsdatetime={latest.get('tsdatetime')} utctstamp={latest.get('utctstamp')}"
    )
    if observed is None:
        reading.warnings.append("station timestamp missing")
    return reading


def parse_vision_payload(data: dict | None, tz_name: str = "Europe/Berlin") -> WindReading:
    """Validate a vision-model JSON object. Temperature and the clock are not wind."""
    reading = WindReading(source="vision", raw_text=str(data))
    if not isinstance(data, dict) or data.get("wind") is None:
        reading.warnings.append("Wind speed not found in vision response")
        return reading
    try:
        base = float(data["wind"])
        gust = float(data["gust"]) if data.get("gust") is not None else None
        temperature = float(data["temperature_c"]) if data.get("temperature_c") is not None else None
    except (TypeError, ValueError) as exc:
        reading.warnings.append(f"vision numbers unreadable: {exc}")
        return reading

    if not _plausible(base) or (gust is not None and not _plausible(gust)):
        reading.warnings.append(f"vision wind {base} kts is outside the plausible range")
        return reading
    if _looks_like_temperature(base, temperature, gust):
        reading.warnings.append(
            f"rejected vision wind {base} because it matches the temperature"
        )
        return reading

    local_time = data.get("local_time") or ""
    observed = _parse_local_datetime(str(local_time), tz_name) if local_time else None
    if observed is not None:
        hour = observed.astimezone(ZoneInfo(tz_name)).hour
        if abs(base - hour) < 0.05 and gust is not None and base > gust + 1:
            reading.warnings.append(f"rejected vision wind {base} because it matches the clock hour")
            return reading

    reading.base_wind_knots = base
    reading.gust_knots = gust
    reading.temperature_c = temperature
    reading.observed_at = observed
    return reading


def station_samples(payload: dict | None) -> list[WindReading]:
    """Every sample in a station payload, newest first. Used to compare with the overlay."""
    if not isinstance(payload, dict):
        return []
    samples = payload.get("measurment") or payload.get("measurement") or {}
    if not isinstance(samples, dict):
        return []
    readings = []
    for sample in samples.values():
        if not isinstance(sample, dict):
            continue
        one = parse_station_payload({"measurment": {"only": sample}})
        if one.base_wind_knots is not None:
            readings.append(one)
    readings.sort(key=lambda item: item.observed_at or datetime.min.replace(tzinfo=timezone.utc), reverse=True)
    return readings


def readings_agree(station: WindReading | None, other: WindReading | None) -> tuple[bool, str]:
    """Whether an overlay/vision reading matches some recent station sample."""
    if station is None or station.base_wind_knots is None:
        return False, "no station reading"
    if other is None or other.base_wind_knots is None:
        detail = "; ".join(other.warnings) if other and other.warnings else "no second reading"
        return False, detail
    if _close(station.base_wind_knots, other.base_wind_knots):
        return True, "matches latest station sample"
    return False, (
        f"station {station.base_wind_knots} kts vs {other.source} {other.base_wind_knots} kts"
    )


def agrees_with_any_sample(samples: list[WindReading], other: WindReading | None) -> tuple[bool, str]:
    """Overlay text can lag the newest minute. Accept any sample inside the tolerance."""
    if other is None or other.base_wind_knots is None:
        detail = "; ".join(other.warnings) if other and other.warnings else "overlay not parsed"
        return False, detail
    if not samples:
        return False, "no station samples"
    for sample in samples:
        if sample.base_wind_knots is not None and _close(sample.base_wind_knots, other.base_wind_knots):
            return True, (
                f"overlay {other.base_wind_knots} kts matches station sample {sample.base_wind_knots} kts"
            )
    latest = samples[0].base_wind_knots
    return False, f"overlay {other.base_wind_knots} kts matches none of the station samples (latest {latest})"


def observed_from_page_url(url: str, tz_name: str) -> datetime | None:
    """Archive URLs use #/YYYY/MM/DD/HHMM in the webcam's local time, not UTC."""
    match = _HASH_RE.search(url or "")
    if not match:
        return None
    local = datetime(
        int(match.group(1)),
        int(match.group(2)),
        int(match.group(3)),
        int(match.group(4)),
        int(match.group(5)),
        tzinfo=ZoneInfo(tz_name),
    )
    return local.astimezone(timezone.utc)


def _plausible(value: float) -> bool:
    return 0.0 <= value <= MAX_PLAUSIBLE_KNOTS


def _close(left: float, right: float) -> bool:
    return abs(left - right) <= STATION_OCR_TOLERANCE_KNOTS


def _looks_like_temperature(wind: float, temperature: float | None, gust: float | None) -> bool:
    if temperature is None:
        return False
    if abs(wind - temperature) >= 0.2:
        return False
    # 15 kt and 15 °C can coincide. Reject only when the gust line is a different knots value,
    # which is how the overlay separates wind from the °C row.
    if gust is None:
        return True
    return abs(gust - temperature) > 1.0


def _clock_hour(text: str) -> int | None:
    match = _TIME_RE.search(text)
    if not match:
        return None
    hour = int(match.group(1))
    if 0 <= hour <= 23:
        return hour
    return None


def _overlay_timestamp(text: str, tz_name: str) -> datetime | None:
    date_match = _DATE_RE.search(text)
    time_match = _TIME_RE.search(text)
    if not date_match or not time_match:
        return None
    day = int(date_match.group(1))
    month = int(date_match.group(2))
    year = int(date_match.group(3))
    hour = int(time_match.group(1))
    minute = int(time_match.group(2))
    try:
        local = datetime(year, month, day, hour, minute, tzinfo=ZoneInfo(tz_name))
    except ValueError:
        return None
    return local.astimezone(timezone.utc)


def _parse_local_datetime(raw: str, tz_name: str) -> datetime | None:
    text = (raw or "").strip()
    if not text:
        return None
    for fmt in ("%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%S"):
        try:
            naive = datetime.strptime(text, fmt)
        except ValueError:
            continue
        return naive.replace(tzinfo=ZoneInfo(tz_name)).astimezone(timezone.utc)
    return None


def _sample_stamp(sample: dict) -> int:
    raw = sample.get("utctstamp")
    try:
        return int(raw)
    except (TypeError, ValueError):
        return 0
