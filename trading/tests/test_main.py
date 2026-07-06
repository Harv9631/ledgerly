import json
import sqlite3
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


def make_broker():
    broker = AsyncMock()
    broker.place_bracket.return_value = 777
    broker.flatten_all.return_value = 0
    return broker


@pytest.fixture
def app_client():
    broker = make_broker()
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


def test_malformed_payload_with_good_secret_returns_422(app_client):
    client, broker = app_client
    r = client.post("/webhook", json={"secret": "s3cret", "action": "nonsense"})
    assert r.status_code == 422
    broker.place_bracket.assert_not_called()


def test_non_json_body_returns_403(app_client):
    client, broker = app_client
    r = client.post(
        "/webhook", content="not json at all",
        headers={"Content-Type": "application/json"},
    )
    assert r.status_code == 403
    broker.place_bracket.assert_not_called()


def test_non_dict_json_body_returns_403(app_client):
    client, broker = app_client
    r = client.post("/webhook", json=["a", "list"])
    assert r.status_code == 403


def test_bad_secret_with_malformed_body_returns_403(app_client):
    client, broker = app_client
    r = client.post("/webhook", json={"secret": "wrong", "action": "nonsense"})
    assert r.status_code == 403
    broker.place_bracket.assert_not_called()


def test_missing_secret_returns_403(app_client):
    client, broker = app_client
    r = client.post("/webhook", json={"action": "buy"})
    assert r.status_code == 403


def test_stored_order_payload_redacts_secret(tmp_path):
    db = str(tmp_path / "trades.db")
    broker = make_broker()
    app = create_app(make_settings(db_path=db), broker=broker)
    client = TestClient(app)
    r = client.post("/webhook", json=make_payload())
    assert r.json()["status"] == "accepted"
    conn = sqlite3.connect(db)
    row = conn.execute("SELECT payload FROM orders").fetchone()
    conn.close()
    assert row is not None
    assert "s3cret" not in row[0]
    assert "secret" not in json.loads(row[0])


def test_modify_stop_accepted_after_entry(app_client):
    client, broker = app_client
    client.post("/webhook", json=make_payload())
    r = client.post("/webhook", json=make_payload(
        action="modify_stop", signal_id="sig-m", stop=21430.0, qty=1
    ))
    assert r.status_code == 200
    assert r.json()["status"] == "accepted"
    broker.modify_stop.assert_awaited_once_with(777, 21430.0, 1)


def test_modify_stop_rejected_after_exit(app_client):
    client, broker = app_client
    client.post("/webhook", json=make_payload())
    client.post("/webhook", json=make_payload(action="exit", signal_id="sig-x"))
    r = client.post("/webhook", json=make_payload(
        action="modify_stop", signal_id="sig-m", stop=21430.0
    ))
    assert r.json()["status"] == "rejected"
    broker.modify_stop.assert_not_called()


def test_modify_stop_rejected_after_halt(app_client):
    client, broker = app_client
    client.post("/webhook", json=make_payload())
    client.post("/halt", json={"secret": "s3cret"})
    r = client.post("/webhook", json=make_payload(
        action="modify_stop", signal_id="sig-m", stop=21430.0
    ))
    assert r.json()["status"] == "rejected"
    broker.modify_stop.assert_not_called()


def test_modify_stop_broker_error_rejected(app_client):
    client, broker = app_client
    client.post("/webhook", json=make_payload())
    broker.modify_stop.side_effect = RuntimeError("boom-detail")
    r = client.post("/webhook", json=make_payload(
        action="modify_stop", signal_id="sig-m", stop=21430.0
    ))
    assert r.status_code == 200
    assert r.json()["status"] == "rejected"
    assert "boom-detail" not in r.json()["reason"]


def test_broker_failure_rejected_generic_and_no_500(app_client):
    client, broker = app_client
    broker.place_bracket.side_effect = RuntimeError("boom-detail")
    r = client.post("/webhook", json=make_payload())
    assert r.status_code == 200
    assert r.json()["status"] == "rejected"
    assert "broker error" in r.json()["reason"]
    assert "boom-detail" not in r.json()["reason"]
    broker.place_bracket.assert_awaited_once()


def test_broker_failure_releases_dedup_reservation(app_client):
    client, broker = app_client
    broker.place_bracket.side_effect = [RuntimeError("boom"), 777]
    client.post("/webhook", json=make_payload())
    r = client.post("/webhook", json=make_payload())  # same signal_id retry
    assert r.json()["status"] == "accepted"
    assert broker.place_bracket.await_count == 2


def test_oversize_qty_rejected_by_risk(app_client):
    client, broker = app_client
    r = client.post("/webhook", json=make_payload(qty=5))
    assert r.json()["status"] == "rejected"
    broker.place_bracket.assert_not_called()


def test_dry_run_entry_accepted_without_broker():
    broker = make_broker()
    app = create_app(make_settings(dry_run=True), broker=broker)
    client = TestClient(app)
    r = client.post("/webhook", json=make_payload())
    assert r.status_code == 200
    assert r.json() == {"status": "accepted", "order_id": None}
    broker.place_bracket.assert_not_called()


def test_halt_in_dry_run_does_not_flatten():
    broker = make_broker()
    app = create_app(make_settings(dry_run=True), broker=broker)
    client = TestClient(app)
    r = client.post("/halt", json={"secret": "s3cret"})
    assert r.status_code == 200
    assert r.json()["flattened"] == 0
    broker.flatten_all.assert_not_called()
    r = client.post("/webhook", json=make_payload())
    assert r.json()["status"] == "rejected"


def test_halt_rejects_bad_secret(app_client):
    client, broker = app_client
    r = client.post("/halt", json={"secret": "wrong"})
    assert r.status_code == 403
    broker.flatten_all.assert_not_called()


def test_health_reports_halted_and_dry_run(app_client):
    client, broker = app_client
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok", "halted": False, "dry_run": False}
    client.post("/halt", json={"secret": "s3cret"})
    r = client.get("/health")
    assert r.json()["halted"] is True
