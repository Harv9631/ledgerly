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


def auth_routes(request):
    """Shared handler fragment for auth endpoints; returns None if unmatched."""
    if request.url.path.endswith("/auth/accesstokenrequest"):
        return httpx.Response(200, json={
            "accessToken": "tok123",
            "expirationTime": "2026-07-06T12:00:00Z",
        })
    if request.url.path.endswith("/account/list"):
        return httpx.Response(200, json=[{"id": 42, "name": "DEMO123"}])
    return None


async def test_authenticate_stores_token_account_and_expiration():
    def handler(request):
        return auth_routes(request) or httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    assert c.access_token == "tok123"
    assert c.account_id == 42
    assert c.token_expiration == "2026-07-06T12:00:00Z"


async def test_authenticate_raises_on_http_error():
    def handler(request):
        return httpx.Response(401)

    c = make_client(handler)
    with pytest.raises(httpx.HTTPStatusError):
        await c.authenticate()


async def test_place_bracket_sends_oso():
    captured = {}

    def handler(request):
        r = auth_routes(request)
        if r:
            return r
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
    assert body["orderQty"] == 1
    assert body["isAutomated"] is True
    assert body["bracket1"]["orderType"] == "Stop"
    assert body["bracket1"]["stopPrice"] == 21418.5
    assert body["bracket1"]["action"] == "Sell"
    assert body["bracket2"]["orderType"] == "Limit"
    assert body["bracket2"]["price"] == 21545.75
    assert body["bracket2"]["action"] == "Sell"


async def test_place_bracket_rejects_invalid_action():
    def handler(request):
        return auth_routes(request) or httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    with pytest.raises(ValueError):
        await c.place_bracket(action="Buy", qty=1, stop=1.0, target=2.0)
    with pytest.raises(ValueError):
        await c.place_bracket(action="close", qty=1, stop=1.0, target=2.0)


async def test_place_bracket_raises_on_failure_reason():
    def handler(request):
        r = auth_routes(request)
        if r:
            return r
        if request.url.path.endswith("/order/placeoso"):
            return httpx.Response(200, json={
                "failureReason": "UnknownReason",
                "failureText": "Insufficient funds",
            })
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    with pytest.raises(RuntimeError) as exc:
        await c.place_bracket(action="buy", qty=1, stop=1.0, target=2.0)
    assert "UnknownReason" in str(exc.value)
    assert "Insufficient funds" in str(exc.value)


async def test_place_bracket_raises_on_http_error():
    def handler(request):
        r = auth_routes(request)
        if r:
            return r
        return httpx.Response(500)

    c = make_client(handler)
    await c.authenticate()
    with pytest.raises(httpx.HTTPStatusError):
        await c.place_bracket(action="buy", qty=1, stop=1.0, target=2.0)


async def test_modify_stop_sends_order_and_qty():
    captured = {}

    def handler(request):
        r = auth_routes(request)
        if r:
            return r
        if request.url.path.endswith("/order/modifyorder"):
            captured["body"] = json.loads(request.content)
            return httpx.Response(200, json={"orderId": 777})
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    await c.modify_stop(order_id=777, new_stop=21430.25, qty=2)
    body = captured["body"]
    assert body["orderId"] == 777
    assert body["orderQty"] == 2
    assert body["orderType"] == "Stop"
    assert body["stopPrice"] == 21430.25
    assert body["isAutomated"] is True


async def test_modify_stop_raises_on_failure_reason():
    def handler(request):
        r = auth_routes(request)
        if r:
            return r
        if request.url.path.endswith("/order/modifyorder"):
            return httpx.Response(200, json={
                "failureReason": "UnknownReason",
                "failureText": "Order not working",
            })
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    with pytest.raises(RuntimeError) as exc:
        await c.modify_stop(order_id=777, new_stop=21430.25, qty=1)
    assert "UnknownReason" in str(exc.value)
    assert "Order not working" in str(exc.value)


async def test_find_working_stop_filters_correctly():
    def handler(request):
        r = auth_routes(request)
        if r:
            return r
        if request.url.path.endswith("/order/list"):
            return httpx.Response(200, json=[
                {"orderId": 1, "accountId": 99, "ordStatus": "Working",
                 "orderType": "Stop"},          # other account
                {"orderId": 2, "accountId": 42, "ordStatus": "Filled",
                 "orderType": "Stop"},          # not working
                {"orderId": 3, "accountId": 42, "ordStatus": "Working",
                 "orderType": "Limit"},         # not a stop
                {"orderId": 4, "accountId": 42, "ordStatus": "Working",
                 "orderType": "Stop"},          # match
            ])
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    assert await c.find_working_stop() == 4


async def test_find_working_stop_returns_none_when_absent():
    def handler(request):
        r = auth_routes(request)
        if r:
            return r
        if request.url.path.endswith("/order/list"):
            return httpx.Response(200, json=[
                {"orderId": 3, "accountId": 42, "ordStatus": "Working",
                 "orderType": "Limit"},
            ])
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    assert await c.find_working_stop() is None


async def test_reauthenticates_once_on_401():
    calls = {"auth": 0, "list": 0}

    def handler(request):
        if request.url.path.endswith("/auth/accesstokenrequest"):
            calls["auth"] += 1
            return httpx.Response(200, json={
                "accessToken": f"tok{calls['auth']}",
                "expirationTime": "2026-07-06T12:00:00Z",
            })
        if request.url.path.endswith("/account/list"):
            return httpx.Response(200, json=[{"id": 42, "name": "DEMO123"}])
        if request.url.path.endswith("/position/list"):
            calls["list"] += 1
            if calls["list"] == 1:
                return httpx.Response(401)
            return httpx.Response(200, json=[
                {"contractId": 9, "netPos": 1, "accountId": 42},
            ])
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    assert calls["auth"] == 1
    positions = await c.open_positions()
    assert calls["auth"] == 2  # re-authenticated after the 401
    assert c.access_token == "tok2"
    assert [p["contractId"] for p in positions] == [9]


async def test_persistent_401_raises():
    def handler(request):
        r = auth_routes(request)
        if r:
            return r
        return httpx.Response(401)

    c = make_client(handler)
    await c.authenticate()
    with pytest.raises(httpx.HTTPStatusError):
        await c.open_positions()


async def test_open_positions_filters_other_accounts_and_flat():
    def handler(request):
        r = auth_routes(request)
        if r:
            return r
        if request.url.path.endswith("/position/list"):
            return httpx.Response(200, json=[
                {"contractId": 9, "netPos": 1, "accountId": 42},
                {"contractId": 10, "netPos": 0, "accountId": 42},
                {"contractId": 11, "netPos": 2, "accountId": 99},
            ])
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    positions = await c.open_positions()
    assert [p["contractId"] for p in positions] == [9]


async def test_flatten_liquidates_open_positions():
    def handler(request):
        r = auth_routes(request)
        if r:
            return r
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


async def test_flatten_is_best_effort_and_reports_failures():
    attempted = []

    def handler(request):
        r = auth_routes(request)
        if r:
            return r
        if request.url.path.endswith("/position/list"):
            return httpx.Response(200, json=[
                {"contractId": 9, "netPos": 1, "accountId": 42},
                {"contractId": 10, "netPos": -1, "accountId": 42},
            ])
        if request.url.path.endswith("/order/liquidateposition"):
            body = json.loads(request.content)
            attempted.append(body["contractId"])
            if body["contractId"] == 9:
                return httpx.Response(500)
            return httpx.Response(200, json={"orderId": 888})
        return httpx.Response(404)

    c = make_client(handler)
    await c.authenticate()
    with pytest.raises(RuntimeError) as exc:
        await c.flatten_all()
    assert attempted == [9, 10]
    assert "9" in str(exc.value)
