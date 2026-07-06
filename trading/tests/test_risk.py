from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from bot.risk import RiskManager

ET = ZoneInfo("America/New_York")


class FakeSettings:
    qty = 1
    max_trades_per_day = 2
    daily_loss_limit = -1000.0
    session_start = "09:45"
    session_end = "15:55"
    stale_seconds = 10


def in_session():
    return datetime(2026, 7, 6, 10, 30, tzinfo=ET)


@pytest.fixture
def rm():
    return RiskManager(FakeSettings())


def test_allows_valid_entry(rm):
    allowed, reason = rm.check_entry(qty=1, now=in_session())
    assert allowed is True


def test_rejects_oversize(rm):
    allowed, reason = rm.check_entry(qty=2, now=in_session())
    assert allowed is False
    assert "position" in reason.lower()


def test_rejects_after_max_trades(rm):
    rm.record_entry(now=in_session())
    rm.record_entry(now=in_session())
    allowed, reason = rm.check_entry(qty=1, now=in_session())
    assert allowed is False
    assert "trades" in reason.lower()


def test_rejects_outside_hours(rm):
    early = datetime(2026, 7, 6, 9, 30, tzinfo=ET)
    allowed, reason = rm.check_entry(qty=1, now=early)
    assert allowed is False
    late = datetime(2026, 7, 6, 16, 0, tzinfo=ET)
    allowed, reason = rm.check_entry(qty=1, now=late)
    assert allowed is False


def test_halts_after_daily_loss_limit(rm):
    rm.record_pnl(-1200.0, now=in_session())
    allowed, reason = rm.check_entry(qty=1, now=in_session())
    assert allowed is False
    assert "loss" in reason.lower() or "halt" in reason.lower()


def test_day_rollover_resets_counters(rm):
    rm.record_entry(now=in_session())
    rm.record_entry(now=in_session())
    next_day = datetime(2026, 7, 7, 10, 30, tzinfo=ET)
    allowed, _ = rm.check_entry(qty=1, now=next_day)
    assert allowed is True


def test_manual_halt(rm):
    rm.halt()
    allowed, reason = rm.check_entry(qty=1, now=in_session())
    assert allowed is False
