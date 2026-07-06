import httpx

from bot.config import Settings


class TradovateClient:
    """Minimal async client for Tradovate demo REST API.

    Access tokens expire (~80 minutes). Authed requests automatically
    re-authenticate once on a 401 and retry; a persistent 401 raises
    httpx.HTTPStatusError.
    """

    def __init__(self, settings: Settings, http: httpx.AsyncClient | None = None):
        self.settings = settings
        self.http = http or httpx.AsyncClient(base_url=settings.tradovate_api_url)
        self.access_token: str | None = None
        self.account_id: int | None = None
        self.token_expiration: str | None = None

    def _auth_headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.access_token}"}

    async def _request(self, method: str, path: str, **kwargs) -> httpx.Response:
        """Authed request; re-auth once on 401 and retry (a 401'd request was
        never executed, so the retry carries no duplicate-order risk)."""
        r = await self.http.request(method, path,
                                    headers=self._auth_headers(), **kwargs)
        if r.status_code == 401:
            await self.authenticate()
            r = await self.http.request(method, path,
                                        headers=self._auth_headers(), **kwargs)
        r.raise_for_status()
        return r

    async def aclose(self) -> None:
        await self.http.aclose()

    async def authenticate(self) -> None:
        r = await self.http.post("/auth/accesstokenrequest", json={
            "name": self.settings.tradovate_username,
            "password": self.settings.tradovate_password,
            "appId": self.settings.tradovate_app_id,
            "appVersion": "1.0",
            "cid": self.settings.tradovate_cid,
            "sec": self.settings.tradovate_sec,
        })
        r.raise_for_status()
        payload = r.json()
        self.access_token = payload["accessToken"]
        self.token_expiration = payload.get("expirationTime")

        r = await self.http.get("/account/list", headers=self._auth_headers())
        r.raise_for_status()
        accounts = r.json()
        if not accounts:
            raise RuntimeError("No Tradovate accounts found")
        self.account_id = accounts[0]["id"]

    async def place_bracket(self, action: str, qty: int,
                            stop: float, target: float) -> int:
        """Market entry with OSO bracket: protective stop + limit target."""
        if action not in ("buy", "sell"):
            raise ValueError(f"invalid action: {action!r}")
        exit_action = "Sell" if action == "buy" else "Buy"
        r = await self._request("POST", "/order/placeoso", json={
            "accountId": self.account_id,
            "action": action.capitalize(),
            "symbol": self.settings.contract_symbol,
            "orderQty": qty,
            "orderType": "Market",
            "isAutomated": True,
            "bracket1": {
                "action": exit_action,
                "orderType": "Stop",
                "stopPrice": stop,
            },
            "bracket2": {
                "action": exit_action,
                "orderType": "Limit",
                "price": target,
            },
        })
        payload = r.json()
        if "orderId" not in payload:
            raise RuntimeError(
                "placeoso rejected: "
                f"{payload.get('failureReason')} - {payload.get('failureText')}"
            )
        return payload["orderId"]

    async def modify_stop(self, order_id: int, new_stop: float, qty: int) -> None:
        r = await self._request("POST", "/order/modifyorder", json={
            "orderId": order_id,
            "orderQty": qty,
            "orderType": "Stop",
            "stopPrice": new_stop,
            "isAutomated": True,
        })
        payload = r.json()
        if payload.get("failureReason"):
            raise RuntimeError(
                "modifyorder rejected: "
                f"{payload.get('failureReason')} - {payload.get('failureText')}"
            )

    async def find_working_stop(self) -> int | None:
        """Return the orderId of the first working protective stop order on
        this account, or None if there is none."""
        r = await self._request("GET", "/order/list")
        for o in r.json():
            if (o.get("accountId") == self.account_id
                    and o.get("ordStatus") == "Working"
                    and o.get("orderType") == "Stop"):
                return o["orderId"]
        return None

    async def open_positions(self) -> list[dict]:
        r = await self._request("GET", "/position/list")
        return [p for p in r.json()
                if p.get("accountId") == self.account_id and p.get("netPos", 0) != 0]

    async def flatten_all(self) -> int:
        """Liquidate every open position, best-effort. Returns count liquidated.

        Attempts every liquidation even if some fail; raises a single
        RuntimeError listing all failures after the loop.
        """
        positions = await self.open_positions()
        failures: list[str] = []
        for p in positions:
            try:
                await self._request("POST", "/order/liquidateposition", json={
                    "accountId": self.account_id,
                    "contractId": p["contractId"],
                    "admin": False,
                })
            except Exception as e:
                failures.append(f"contractId={p['contractId']}: {e}")
        if failures:
            raise RuntimeError("flatten_all failures: " + "; ".join(failures))
        return len(positions)
