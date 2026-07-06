import json
import logging
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from fastapi import FastAPI, HTTPException, Request
from pydantic import ValidationError

from bot.config import Settings
from bot.models import Signal
from bot.risk import RiskManager
from bot.store import Store

log = logging.getLogger("bot")
ET = ZoneInfo("America/New_York")


def create_app(settings: Settings, broker) -> FastAPI:
    app = FastAPI()
    store = Store(settings.db_path)
    risk = RiskManager(settings)
    state = {"last_entry_order_id": None}

    def _reject(sig: Signal, reason: str) -> dict:
        store.record_signal(sig.signal_id, sig.action, accepted=False, reason=reason)
        log.warning("REJECTED %s: %s", sig.signal_id, reason)
        return {"status": "rejected", "reason": reason}

    @app.post("/webhook")
    async def webhook(request: Request):
        body = await request.json()
        try:
            sig = Signal(**body)
        except ValidationError as e:
            raise HTTPException(status_code=422, detail=e.errors(include_url=False))

        if sig.secret != settings.webhook_secret:
            raise HTTPException(status_code=403, detail="bad secret")

        now = datetime.now(timezone.utc)

        if sig.age_seconds(now) > settings.stale_seconds:
            return _reject(sig, f"stale signal (> {settings.stale_seconds}s)")

        if store.seen(sig.signal_id):
            return _reject(sig, "duplicate signal_id")

        if sig.action == "exit":
            if not settings.dry_run:
                await broker.flatten_all()
            store.record_signal(sig.signal_id, sig.action, accepted=True, reason="exit")
            return {"status": "accepted", "action": "exit"}

        if sig.action == "modify_stop":
            order_id = state["last_entry_order_id"]
            if order_id is None:
                return _reject(sig, "no active bracket order to modify")
            if not settings.dry_run:
                await broker.modify_stop(order_id, sig.stop, sig.qty)
            store.record_signal(sig.signal_id, sig.action, accepted=True,
                                reason="stop moved")
            return {"status": "accepted", "action": "modify_stop"}

        # buy / sell entry
        allowed, reason = risk.check_entry(sig.qty, now)
        if not allowed:
            return _reject(sig, reason)

        if settings.dry_run:
            order_id = None
            log.info("DRY RUN: would place %s bracket for %s", sig.action, sig.signal_id)
        else:
            try:
                order_id = await broker.place_bracket(
                    action=sig.action, qty=sig.qty,
                    stop=sig.stop, target=sig.target2,
                )
            except Exception as e:  # missed trade is safer than a retry-duplicate
                log.error("ORDER FAILED for %s: %s -- NOT retrying", sig.signal_id, e)
                return _reject(sig, f"broker error: {e}")

        state["last_entry_order_id"] = order_id
        risk.record_entry(now)
        store.record_signal(sig.signal_id, sig.action, accepted=True, reason="ok")
        store.record_order(sig.signal_id, str(order_id), json.dumps(body))
        return {"status": "accepted", "order_id": order_id}

    @app.post("/halt")
    async def halt(request: Request):
        body = await request.json()
        if body.get("secret") != settings.webhook_secret:
            raise HTTPException(status_code=403, detail="bad secret")
        risk.halt()
        flattened = await broker.flatten_all()
        log.warning("KILL SWITCH: halted, %d position(s) flattened", flattened)
        return {"status": "halted", "flattened": flattened}

    @app.get("/health")
    async def health():
        return {"status": "ok", "halted": risk.halted, "dry_run": settings.dry_run}

    return app


def run():
    from contextlib import asynccontextmanager

    import uvicorn

    from bot.config import load_settings
    from bot.tradovate import TradovateClient

    logging.basicConfig(level=logging.INFO)
    settings = load_settings()
    broker = TradovateClient(settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if not settings.dry_run:
            await broker.authenticate()
            positions = await broker.open_positions()
            if positions:
                log.warning("Resuming with %d open position(s)", len(positions))
        yield
        await broker.aclose()

    app = create_app(settings, broker)
    app.router.lifespan_context = lifespan
    uvicorn.run(app, host="127.0.0.1", port=8000)


if __name__ == "__main__":
    run()
