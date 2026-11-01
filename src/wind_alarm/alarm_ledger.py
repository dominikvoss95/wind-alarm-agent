"""One alarm push per location per Berlin day.

GitHub-hosted runners do not share a disk. The workflow restores this file
from the Actions cache. Lambda, with USE_AWS, also reads and writes the same
shape of document in S3 so five-minute EventBridge runs do not stack pushes.
"""

from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from wind_alarm.config import config
from wind_alarm.logger import get_logger

logger = get_logger("wind_alarm.ledger")
BERLIN = ZoneInfo("Europe/Berlin")


def berlin_today() -> str:
    return datetime.now(BERLIN).date().isoformat()


def notifications_enabled() -> bool:
    raw = os.environ.get("WIND_ALARM_SEND", "true").strip().lower()
    return raw not in {"0", "false", "no", "off"}


class AlarmLedger:
    """Maps a location id to the Berlin date an alarm was last sent."""

    def __init__(self, path: Path | None = None):
        if path is not None:
            self.path = path
        else:
            override = os.environ.get("WIND_ALARM_LEDGER")
            self.path = Path(override) if override else config.DEBUG_DIR / "alarm-ledger.json"

    def already_sent(self, location_id: str, day: str | None = None) -> bool:
        day = day or berlin_today()
        return self._read().get(location_id) == day

    def mark_sent(self, location_id: str, day: str | None = None) -> None:
        day = day or berlin_today()
        record = self._read()
        record[location_id] = day
        self._write(record)

    def _read(self) -> dict:
        record: dict = {}
        if self.path.exists():
            try:
                loaded = json.loads(self.path.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    record.update({str(k): str(v) for k, v in loaded.items()})
            except (OSError, json.JSONDecodeError) as exc:
                logger.warning("alarm ledger unreadable: %s", exc)
        remote = _s3_read()
        if remote:
            record.update(remote)
        return record

    def _write(self, record: dict) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(record, sort_keys=True), encoding="utf-8")
        _s3_write(record)


def _s3_read() -> dict | None:
    if not config.USE_AWS:
        return None
    try:
        import boto3
        bucket = os.environ.get("WIND_ALARM_BUCKET", "")
        if not bucket:
            return None
        body = boto3.client("s3").get_object(Bucket=bucket, Key="alarm-ledger.json")["Body"].read()
        loaded = json.loads(body)
        if isinstance(loaded, dict):
            return {str(k): str(v) for k, v in loaded.items()}
    except Exception as exc:  # pylint: disable=broad-exception-caught
        logger.warning("alarm ledger s3 read failed: %s", exc)
    return None


def _s3_write(record: dict) -> None:
    if not config.USE_AWS:
        return
    try:
        import boto3
        bucket = os.environ.get("WIND_ALARM_BUCKET", "")
        if not bucket:
            return
        boto3.client("s3").put_object(
            Bucket=bucket,
            Key="alarm-ledger.json",
            Body=json.dumps(record, sort_keys=True).encode("utf-8"),
            ContentType="application/json",
        )
    except Exception as exc:  # pylint: disable=broad-exception-caught
        logger.warning("alarm ledger s3 write failed: %s", exc)
