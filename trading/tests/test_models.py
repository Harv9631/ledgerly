from datetime import datetime, timedelta, timezone

import pytest
from pydantic import ValidationError

from bot.models import Signal


def make_payload(**overrides):
    p = {
        "secret": "s3cret",
        "action": "buy",
        "symbol": "NQ",
        "qty": 1,
        "entry": 21450.25,
        "stop": 21418.50,
        "target1": 21498.00,
        "target2": 21545.75,
        "signal_id": "orb-sweep-long-2026-07-06",
        "sent_at": datetime.now(timezone.utc).isoformat(),
    }
    p.update(overrides)
    return p


def test_parses_valid_payload():
    s = Signal(**make_payload())
    assert s.action == "buy"
    assert s.entry == 21450.25


def test_rejects_unknown_action():
    with pytest.raises(ValidationError):
        Signal(**make_payload(action="yolo"))


def test_age_seconds():
    old = (datetime.now(timezone.utc) - timedelta(seconds=30)).isoformat()
    s = Signal(**make_payload(sent_at=old))
    assert s.age_seconds() >= 29


def test_modify_stop_requires_stop_price():
    s = Signal(**make_payload(action="modify_stop", stop=21450.0))
    assert s.stop == 21450.0
    with pytest.raises(ValidationError):
        Signal(**make_payload(action="modify_stop", stop=0))
    payload = make_payload(action="modify_stop")
    del payload["stop"]
    with pytest.raises(ValidationError):
        Signal(**payload)


def test_entry_requires_positive_stop():
    with pytest.raises(ValidationError):
        Signal(**make_payload(action="buy", stop=0))
    with pytest.raises(ValidationError):
        Signal(**make_payload(action="sell", stop=0))


def test_entry_requires_positive_target2():
    with pytest.raises(ValidationError):
        Signal(**make_payload(action="buy", target2=0))
    with pytest.raises(ValidationError):
        Signal(**make_payload(action="sell", target2=0))


def test_exit_allows_zero_prices():
    s = Signal(**make_payload(action="exit", stop=0, target2=0))
    assert s.action == "exit"


def test_rejects_invalid_qty():
    with pytest.raises(ValidationError):
        Signal(**make_payload(qty=0))


def test_rejects_nan_price():
    with pytest.raises(ValidationError):
        Signal(**make_payload(entry="NaN"))


def test_secret_not_in_repr():
    s = Signal(**make_payload())
    assert "s3cret" not in repr(s)
