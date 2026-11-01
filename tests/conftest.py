"""Keep alarm-ledger files from one test from suppressing the next."""

import pytest


@pytest.fixture(autouse=True)
def isolated_alarm_ledger(tmp_path, monkeypatch):
    monkeypatch.setenv("WIND_ALARM_LEDGER", str(tmp_path / "ledger.json"))
    monkeypatch.delenv("WIND_ALARM_SEND", raising=False)
