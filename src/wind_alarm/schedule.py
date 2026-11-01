"""Local alarm windows and the UTC crons that cover them in both CET and CEST.

Europe/Berlin is UTC+1 in winter (CET) and UTC+2 in summer (CEST). A cron
written only for CEST misses the late winter hour, and one written only for
CET starts an hour late in summer. The UTC hour range is the union, so the
local window is inside the schedule all year. The extra hour on either side
is intentional.
"""

from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

BERLIN = ZoneInfo("Europe/Berlin")

# Inclusive local clock times that must have a scheduled check.
# Kochelsee 05:00-08:00, Gardasee Pelér 05:00-10:00.
def parse_hhmm(value: str) -> time:
    hour, minute = value.split(":")
    return time(int(hour), int(minute))


def utc_clocks(hour_expr: str, minute_step: int) -> list[tuple[int, int]]:
    """UTC (hour, minute) pairs a `*/step H1-H2` cron fires on one day."""
    start_s, end_s = hour_expr.split("-")
    clocks = []
    for hour in range(int(start_s), int(end_s) + 1):
        minute = 0
        while minute < 60:
            clocks.append((hour, minute))
            minute += minute_step
    return clocks


def local_instants_covered(hour_expr: str, minute_step: int, on: date) -> set[datetime]:
    """Berlin times on `on` that this UTC cron actually fires."""
    covered = set()
    for hour, minute in utc_clocks(hour_expr, minute_step):
        moment = datetime(on.year, on.month, on.day, hour, minute, tzinfo=timezone.utc)
        local = moment.astimezone(BERLIN)
        if local.date() == on:
            covered.add(local.replace(second=0, microsecond=0))
    return covered


def window_marks(on: date, start: time, end: time, step_minutes: int) -> list[datetime]:
    """Every step from start through end, inclusive, on a Berlin calendar day."""
    cursor = datetime.combine(on, start, tzinfo=BERLIN)
    stop = datetime.combine(on, end, tzinfo=BERLIN)
    marks = []
    while cursor <= stop:
        marks.append(cursor)
        cursor += timedelta(minutes=step_minutes)
    return marks


def cron_covers_local_window(
    hour_expr: str,
    minute_step: int,
    start: time,
    end: time,
    on: date,
) -> list[datetime]:
    """Local marks in the window that this cron does not fire. Empty means covered."""
    covered = local_instants_covered(hour_expr, minute_step, on)
    return [mark for mark in window_marks(on, start, end, minute_step) if mark not in covered]


# A winter day (CET) and a summer day (CEST).
CET_DAY = date(2026, 1, 15)
CEST_DAY = date(2026, 7, 15)
