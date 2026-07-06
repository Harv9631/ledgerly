import json

import httpx
import pytest

from bot.config import Settings
from bot.tradovate import TradovateClient


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


def make_client(handler):
    settings = make_settings()
    transport = httpx.MockTransport(handler)
    http = httpx.AsyncClient(transport=transport,
                             base_url=settings.tradovate_api_url)
    return TradovateClient(settings, http=http)


@pytest.mark.asyncio
async def test_authenticate_stores_token_and_account():
    def handler(request):
        if request.url.path.endswith("/auth/accesstokenrequest"):
            return httpx.Response(200, json={"accessToken": "tok123"})
        if request.url.path.endswith("/account/list"):
            return httpx.Response(200, json=[{"id": 42, "name": "DEMO123"}])
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    assert c.access_token == "tok123"
    assert c.account_id == 42


@pytest.mark.asyncio
async def test_place_bracket_sends_oso():
    captured = {}

    def handler(request):
        if request.url.path.endswith("/auth/accesstokenrequest"):
            return httpx.Response(200, json={"accessToken": "tok"})
        if request.url.path.endswith("/account/list"):
            return httpx.Response(200, json=[{"id": 42, "name": "DEMO123"}])
        if request.url.path.endswith("/order/placeoso"):
            captured["body"] = json.loads(request.content)
            return httpx.Response(200, json={"orderId": 777})
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    order_id = await c.place_bracket(
        action="buy", qty=1, stop=21418.5, target=21545.75
    )
    assert order_id == 777
    body = captured["body"]
    assert body["action"] == "Buy"
    assert body["symbol"] == "NQU6"
    assert body["isAutomated"] is True
    assert body["bracket1"]["orderType"] == "Stop"
    assert body["bracket2"]["orderType"] == "Limit"


@pytest.mark.asyncio
async def test_flatten_liquidates_open_positions():
    def handler(request):
        if request.url.path.endswith("/auth/accesstokenrequest"):
            return httpx.Response(200, json={"accessToken": "tok"})
        if request.url.path.endswith("/account/list"):
            return httpx.Response(200, json=[{"id": 42, "name": "DEMO123"}])
        if request.url.path.endswith("/position/list"):
            return httpx.Response(200, json=[
                {"contractId": 9, "netPos": 1, "accountId": 42}
            ])
        if request.url.path.endswith("/order/liquidateposition"):
            return httpx.Response(200, json={"orderId": 888})
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    liquidated = await c.flatten_all()
    assert liquidated == 1
