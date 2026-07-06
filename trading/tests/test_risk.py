from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from bot.config import Settings
from bot.risk import RiskManager

ET = ZoneInfo("America/New_York")


def make_settings(**overrides) -> Settings:
    base = dict(
        symbol="NQ",
        qty=1,
        max_contracts=1,
        max_trades_per_day=2,
        daily_loss_limit=-1000.0,
        session_start="09:45",
        session_end="15:55",
        stale_seconds=10,
        db_path="trades.db",
        webhook_secret="s3cret",
        tradovate_username="u",
        tradovate_password="p",
        tradovate_app_id="app",
        tradovate_cid="1",
        tradovate_sec="sec",
        tradovate_api_url="https://demo.tradovateapi.com/v1",
        contract_symbol="NQU6",
        dry_run=True,
    )
    base.update(overrides)
    return Settings(**base)


def in_session():
    return datetime(2026, 7, 6, 10, 30, tzinfo=ET)


@pytest.fixture
def rm():
    return RiskManager(make_settings())


def test_allows_valid_entry(rm):
    allowed, reason = rm.check_entry(qty=1, now=in_session())
    assert allowed is True


def test_rejects_oversize(rm):
    allowed, reason = rm.check_entry(qty=2, now=in_session())
    assert allowed is False
    assert "position" in reason.lower()


def test_max_contracts_independent_of_qty():
    rm = RiskManager(make_settings(qty=3, max_contracts=1))
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


def test_outside_hours_reason_uses_settings():
    rm = RiskManager(make_settings(session_start="10:00", session_end="14:00"))
    allowed, reason = rm.check_entry(qty=1, now=datetime(2026, 7, 6, 9, 30, tzinfo=ET))
    assert allowed is False
    assert "10:00" in reason
    assert "14:00" in reason


def test_accepts_session_boundaries(rm):
    start = datetime(2026, 7, 6, 9, 45, 0, tzinfo=ET)
    allowed, _ = rm.check_entry(qty=1, now=start)
    assert allowed is True
    end = datetime(2026, 7, 6, 15, 55, 0, tzinfo=ET)
    allowed, _ = rm.check_entry(qty=1, now=end)
    assert allowed is True


def test_halts_after_daily_loss_limit(rm):
    rm.record_pnl(-1200.0, now=in_session())
    allowed, reason = rm.check_entry(qty=1, now=in_session())
    assert allowed is False
    assert "loss" in reason.lower() or "halt" in reason.lower()


def test_exact_loss_limit_triggers_halt(rm):
    rm.record_pnl(-1000.0, now=in_session())
    assert rm.halted is True
    allowed, reason = rm.check_entry(qty=1, now=in_session())
    assert allowed is False


def test_day_rollover_resets_counters(rm):
    rm.record_entry(now=in_session())
    rm.record_entry(now=in_session())
    next_day = datetime(2026, 7, 7, 10, 30, tzinfo=ET)
    allowed, _ = rm.check_entry(qty=1, now=next_day)
    assert allowed is True


def test_day_rollover_clears_halt(rm):
    rm.record_pnl(-1200.0, now=in_session())
    assert rm.halted is True
    next_day = datetime(2026, 7, 7, 10, 30, tzinfo=ET)
    allowed, _ = rm.check_entry(qty=1, now=next_day)
    assert allowed is True
    assert rm.halted is False


def test_manual_halt(rm):
    rm.halt()
    allowed, reason = rm.check_entry(qty=1, now=in_session())
    assert allowed is False


def test_rejects_naive_datetime(rm):
    naive = datetime(2026, 7, 6, 10, 30)
    with pytest.raises(ValueError):
        rm.check_entry(qty=1, now=naive)
    with pytest.raises(ValueError):
        rm.record_entry(now=naive)
    with pytest.raises(ValueError):
        rm.record_pnl(-100.0, now=naive)
