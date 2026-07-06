from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from bot.config import Settings
from bot.main import create_app


def make_settings(**overrides) -> Settings:
    base = dict(
        symbol="NQ",
        qty=1,
        max_contracts=1,
        max_trades_per_day=2,
        daily_loss_limit=-1000.0,
        session_start="00:00",  # wide-open session so tests don't depend on clock
        session_end="23:59",
        stale_seconds=10,
        db_path=":memory:",
        webhook_secret="s3cret",
        tradovate_username="u",
        tradovate_password="p",
        tradovate_app_id="app",
        tradovate_cid="1",
        tradovate_sec="sec",
        tradovate_api_url="https://demo.tradovateapi.com/v1",
        contract_symbol="NQU6",
        dry_run=False,
    )
    base.update(overrides)
    return Settings(**base)


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
        "signal_id": "sig-1",
        "sent_at": datetime.now(timezone.utc).isoformat(),
    }
    p.update(overrides)
    return p


@pytest.fixture
def app_client():
    broker = AsyncMock()
    broker.place_bracket.return_value = 777
    broker.flatten_all.return_value = 0
    app = create_app(make_settings(), broker=broker)
    return TestClient(app), broker


def test_rejects_bad_secret(app_client):
    client, broker = app_client
    r = client.post("/webhook", json=make_payload(secret="wrong"))
    assert r.status_code == 403
    broker.place_bracket.assert_not_called()


def test_accepts_buy_and_places_bracket(app_client):
    client, broker = app_client
    r = client.post("/webhook", json=make_payload())
    assert r.status_code == 200
    assert r.json()["status"] == "accepted"
    broker.place_bracket.assert_awaited_once_with(
        action="buy", qty=1, stop=21418.50, target=21545.75
    )


def test_deduplicates_signal_id(app_client):
    client, broker = app_client
    client.post("/webhook", json=make_payload())
    r = client.post("/webhook", json=make_payload())
    assert r.status_code == 200
    assert r.json()["status"] == "rejected"
    assert broker.place_bracket.await_count == 1


def test_rejects_stale_signal(app_client):
    client, broker = app_client
    old = (datetime.now(timezone.utc) - timedelta(seconds=60)).isoformat()
    r = client.post("/webhook", json=make_payload(sent_at=old))
    assert r.json()["status"] == "rejected"
    broker.place_bracket.assert_not_called()


def test_exit_flattens(app_client):
    client, broker = app_client
    r = client.post("/webhook", json=make_payload(action="exit", signal_id="sig-x"))
    assert r.status_code == 200
    broker.flatten_all.assert_awaited_once()


def test_halt_endpoint_flattens_and_blocks(app_client):
    client, broker = app_client
    r = client.post("/halt", json={"secret": "s3cret"})
    assert r.status_code == 200
    broker.flatten_all.assert_awaited_once()
    r = client.post("/webhook", json=make_payload(signal_id="sig-2"))
    assert r.json()["status"] == "rejected"


def test_malformed_payload_returns_422(app_client):
    client, broker = app_client
    r = client.post("/webhook", json={"secret": "s3cret", "action": "nonsense"})
    assert r.status_code == 422
    broker.place_bracket.assert_not_called()
