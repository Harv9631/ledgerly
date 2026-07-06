import pytest
from bot.config import load_settings


BASE_ENV = {
    "WEBHOOK_SECRET": "s3cret",
    "TRADOVATE_USERNAME": "u",
    "TRADOVATE_PASSWORD": "p",
    "TRADOVATE_APP_ID": "app",
    "TRADOVATE_CID": "1",
    "TRADOVATE_SEC": "sec",
    "TRADOVATE_API_URL": "https://demo.tradovateapi.com/v1",
    "CONTRACT_SYMBOL": "NQU6",
    "DRY_RUN": "1",
}


def set_env(monkeypatch, overrides=None):
    env = {**BASE_ENV, **(overrides or {})}
    for k, v in env.items():
        monkeypatch.setenv(k, v)


def test_loads_settings(monkeypatch):
    set_env(monkeypatch)
    s = load_settings()
    assert s.symbol == "NQ"
    assert s.qty == 1
    assert s.max_trades_per_day == 2
    assert s.daily_loss_limit == -1000.0
    assert s.webhook_secret == "s3cret"
    assert s.dry_run is True


def test_rejects_live_api_url(monkeypatch):
    set_env(monkeypatch, {"TRADOVATE_API_URL": "https://live.tradovateapi.com/v1"})
    with pytest.raises(RuntimeError, match="DEMO"):
        load_settings()


def test_rejects_demo_lookalike_url(monkeypatch):
    set_env(monkeypatch, {"TRADOVATE_API_URL": "https://demo.tradovateapi.com.attacker.io/v1"})
    with pytest.raises(RuntimeError, match="DEMO"):
        load_settings()


def test_rejects_live_url_with_demo_in_query(monkeypatch):
    set_env(
        monkeypatch,
        {"TRADOVATE_API_URL": "https://live.tradovateapi.com/v1?ref=demo.tradovateapi.com"},
    )
    with pytest.raises(RuntimeError, match="DEMO"):
        load_settings()


def test_dry_run_accepts_true(monkeypatch):
    set_env(monkeypatch, {"DRY_RUN": "true"})
    s = load_settings()
    assert s.dry_run is True


def test_rejects_garbage_dry_run(monkeypatch):
    set_env(monkeypatch, {"DRY_RUN": "banana"})
    with pytest.raises(RuntimeError):
        load_settings()
