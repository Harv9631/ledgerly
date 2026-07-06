# NQ ORB + Liquidity Sweep Bot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a TradingView → webhook → Tradovate DEMO pipeline that trades an ORB + liquidity-sweep strategy on NQ in simulation, with bot-side risk guardrails and trade logging.

**Architecture:** Pine Script on TradingView owns all strategy logic and fires JSON alerts through ngrok to a local FastAPI server. The Python bot validates, applies risk guardrails, places bracket orders on Tradovate's demo API, and logs everything to SQLite. The bot never originates trades.

**Tech Stack:** Python 3.11+, FastAPI, uvicorn, httpx, pydantic v2, PyYAML, python-dotenv, pytest, SQLite (stdlib), Pine Script v5.

**Spec deviations (approved rationale):**
1. Partial exit at 1.5R requires ≥2 contracts; max position is 1. Instead: full exit at `target2`, and Pine sends a `modify_stop` alert to move the stop to breakeven when 1.5R is reached.
2. WebSocket fill tracking is deferred to V1.1. V1 polls `/position/list` and `/fill/list` via REST after each order and on startup, which still means the bot tracks actual broker state, never assumed state.

**Working directory for all commands:** `C:\Users\harve\trading`

---

### Task 1: Project scaffolding

**Files:**
- Create: `requirements.txt`, `.env.example`, `.gitignore`, `config/settings.yaml`, `bot/__init__.py`, `tests/__init__.py`

- [ ] **Step 1: Create directory structure and files**

`requirements.txt`:
```
fastapi>=0.115
uvicorn>=0.30
httpx>=0.27
pydantic>=2.7
pyyaml>=6.0
python-dotenv>=1.0
pytest>=8.0
pytest-asyncio>=0.23
```

`.env.example`:
```
WEBHOOK_SECRET=change-me
TRADOVATE_USERNAME=
TRADOVATE_PASSWORD=
TRADOVATE_APP_ID=
TRADOVATE_CID=
TRADOVATE_SEC=
TRADOVATE_API_URL=https://demo.tradovateapi.com/v1
CONTRACT_SYMBOL=NQU6
DRY_RUN=1
```

`.gitignore`:
```
.env
__pycache__/
*.db
.pytest_cache/
venv/
```

`config/settings.yaml`:
```yaml
symbol: NQ
qty: 1
max_trades_per_day: 2
daily_loss_limit: -1000.0
session_start: "09:45"
session_end: "15:55"
stale_seconds: 10
db_path: trades.db
```

`bot/__init__.py` and `tests/__init__.py`: empty files.

- [ ] **Step 2: Create venv and install**

Run: `python -m venv venv && venv/Scripts/pip install -r requirements.txt`
Expected: all packages install without error.

- [ ] **Step 3: Verify pytest runs**

Run: `venv/Scripts/pytest --collect-only`
Expected: "no tests ran" (collects zero tests, exit without import errors).

- [ ] **Step 4: Commit**

```bash
git add requirements.txt .env.example .gitignore config/settings.yaml bot/__init__.py tests/__init__.py
git commit -m "chore: scaffold NQ trading bot project"
```

---

### Task 2: Config loader with demo-only enforcement

**Files:**
- Create: `bot/config.py`
- Test: `tests/test_config.py`

- [ ] **Step 1: Write the failing tests**

`tests/test_config.py`:
```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `venv/Scripts/pytest tests/test_config.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'bot.config'`

- [ ] **Step 3: Write the implementation**

`bot/config.py`:
```python
import os
from dataclasses import dataclass
from pathlib import Path

import yaml
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SETTINGS_YAML = PROJECT_ROOT / "config" / "settings.yaml"


@dataclass(frozen=True)
class Settings:
    symbol: str
    qty: int
    max_trades_per_day: int
    daily_loss_limit: float
    session_start: str
    session_end: str
    stale_seconds: int
    db_path: str
    webhook_secret: str
    tradovate_username: str
    tradovate_password: str
    tradovate_app_id: str
    tradovate_cid: str
    tradovate_sec: str
    tradovate_api_url: str
    contract_symbol: str
    dry_run: bool


def load_settings(yaml_path: Path = SETTINGS_YAML) -> Settings:
    load_dotenv(PROJECT_ROOT / ".env")
    with open(yaml_path) as f:
        y = yaml.safe_load(f)

    api_url = os.environ["TRADOVATE_API_URL"]
    if "demo.tradovateapi.com" not in api_url:
        raise RuntimeError(
            "V1 supports DEMO accounts only. TRADOVATE_API_URL must point at "
            "demo.tradovateapi.com. Refusing to start."
        )

    return Settings(
        symbol=y["symbol"],
        qty=int(y["qty"]),
        max_trades_per_day=int(y["max_trades_per_day"]),
        daily_loss_limit=float(y["daily_loss_limit"]),
        session_start=y["session_start"],
        session_end=y["session_end"],
        stale_seconds=int(y["stale_seconds"]),
        db_path=y["db_path"],
        webhook_secret=os.environ["WEBHOOK_SECRET"],
        tradovate_username=os.environ["TRADOVATE_USERNAME"],
        tradovate_password=os.environ["TRADOVATE_PASSWORD"],
        tradovate_app_id=os.environ["TRADOVATE_APP_ID"],
        tradovate_cid=os.environ["TRADOVATE_CID"],
        tradovate_sec=os.environ["TRADOVATE_SEC"],
        tradovate_api_url=api_url,
        contract_symbol=os.environ["CONTRACT_SYMBOL"],
        dry_run=os.environ.get("DRY_RUN", "1") == "1",
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `venv/Scripts/pytest tests/test_config.py -v`
Expected: 2 PASS

- [ ] **Step 5: Commit**

```bash
git add bot/config.py tests/test_config.py
git commit -m "feat: config loader with demo-only enforcement"
```

---

### Task 3: Signal model and validation

**Files:**
- Create: `bot/models.py`
- Test: `tests/test_models.py`

- [ ] **Step 1: Write the failing tests**

`tests/test_models.py`:
```python
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


def test_rejects_invalid_qty():
    with pytest.raises(ValidationError):
        Signal(**make_payload(qty=0))


def test_rejects_nan_price():
    with pytest.raises(ValidationError):
        Signal(**make_payload(entry="NaN"))


def test_secret_not_in_repr():
    s = Signal(**make_payload())
    assert "s3cret" not in repr(s)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `venv/Scripts/pytest tests/test_models.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'bot.models'`

- [ ] **Step 3: Write the implementation**

`bot/models.py`:
```python
from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field, model_validator


class Signal(BaseModel):
    secret: str = Field(repr=False)
    action: Literal["buy", "sell", "exit", "modify_stop"]
    symbol: str
    qty: int = Field(1, ge=1, le=10)
    entry: float = Field(0.0, ge=0, allow_inf_nan=False)
    stop: float = Field(0.0, ge=0, allow_inf_nan=False)
    target1: float = Field(0.0, ge=0, allow_inf_nan=False)
    target2: float = Field(0.0, ge=0, allow_inf_nan=False)
    signal_id: str
    sent_at: datetime

    @model_validator(mode="after")
    def _modify_stop_requires_stop(self) -> "Signal":
        if self.action == "modify_stop" and self.stop <= 0:
            raise ValueError("modify_stop requires a positive stop price")
        return self

    def age_seconds(self, now: datetime | None = None) -> float:
        now = now or datetime.now(timezone.utc)
        sent = self.sent_at
        if sent.tzinfo is None:
            sent = sent.replace(tzinfo=timezone.utc)
        return (now - sent).total_seconds()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `venv/Scripts/pytest tests/test_models.py -v`
Expected: 7 PASS

- [ ] **Step 5: Commit**

```bash
git add bot/models.py tests/test_models.py
git commit -m "feat: webhook signal model with staleness check"
```

---

### Task 4: SQLite store (signals, orders, fills, dedup)

**Files:**
- Create: `bot/store.py`
- Test: `tests/test_store.py`

- [ ] **Step 1: Write the failing tests**

`tests/test_store.py`:
```python
from bot.store import Store


def make_store(tmp_path):
    return Store(str(tmp_path / "test.db"))


def test_record_and_dedup_signal(tmp_path):
    st = make_store(tmp_path)
    assert st.seen("sig-1") is False
    st.record_signal("sig-1", "buy", accepted=True, reason="ok")
    assert st.seen("sig-1") is True


def test_record_fill_and_daily_pnl(tmp_path):
    st = make_store(tmp_path)
    st.record_fill("sig-1", side="buy", qty=1, price=21450.0, pnl=0.0, day="2026-07-06")
    st.record_fill("sig-1", side="sell", qty=1, price=21470.0, pnl=400.0, day="2026-07-06")
    assert st.daily_pnl("2026-07-06") == 400.0
    assert st.daily_pnl("2026-07-07") == 0.0


def test_all_fills_ordered(tmp_path):
    st = make_store(tmp_path)
    st.record_fill("a", side="buy", qty=1, price=1.0, pnl=0.0, day="2026-07-06")
    st.record_fill("b", side="sell", qty=1, price=2.0, pnl=100.0, day="2026-07-06")
    fills = st.all_fills()
    assert len(fills) == 2
    assert fills[0]["signal_id"] == "a"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `venv/Scripts/pytest tests/test_store.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'bot.store'`

- [ ] **Step 3: Write the implementation**

`bot/store.py`:
```python
import sqlite3
from datetime import datetime, timezone

SCHEMA = """
CREATE TABLE IF NOT EXISTS signals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signal_id TEXT NOT NULL,
    action TEXT NOT NULL,
    accepted INTEGER NOT NULL,
    reason TEXT NOT NULL,
    received_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signal_id TEXT NOT NULL,
    broker_order_id TEXT,
    payload TEXT NOT NULL,
    placed_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS fills (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signal_id TEXT NOT NULL,
    side TEXT NOT NULL,
    qty INTEGER NOT NULL,
    price REAL NOT NULL,
    pnl REAL NOT NULL,
    day TEXT NOT NULL,
    filled_at TEXT NOT NULL
);
"""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class Store:
    def __init__(self, path: str):
        self.conn = sqlite3.connect(path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript(SCHEMA)
        self.conn.commit()

    def seen(self, signal_id: str) -> bool:
        row = self.conn.execute(
            "SELECT 1 FROM signals WHERE signal_id = ? AND accepted = 1 LIMIT 1",
            (signal_id,),
        ).fetchone()
        return row is not None

    def record_signal(self, signal_id: str, action: str, accepted: bool, reason: str):
        self.conn.execute(
            "INSERT INTO signals (signal_id, action, accepted, reason, received_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (signal_id, action, int(accepted), reason, _now()),
        )
        self.conn.commit()

    def record_order(self, signal_id: str, broker_order_id: str | None, payload: str):
        self.conn.execute(
            "INSERT INTO orders (signal_id, broker_order_id, payload, placed_at) "
            "VALUES (?, ?, ?, ?)",
            (signal_id, broker_order_id, payload, _now()),
        )
        self.conn.commit()

    def record_fill(self, signal_id: str, side: str, qty: int, price: float,
                    pnl: float, day: str):
        self.conn.execute(
            "INSERT INTO fills (signal_id, side, qty, price, pnl, day, filled_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (signal_id, side, qty, price, pnl, day, _now()),
        )
        self.conn.commit()

    def daily_pnl(self, day: str) -> float:
        row = self.conn.execute(
            "SELECT COALESCE(SUM(pnl), 0) AS total FROM fills WHERE day = ?", (day,)
        ).fetchone()
        return float(row["total"])

    def all_fills(self) -> list[dict]:
        rows = self.conn.execute("SELECT * FROM fills ORDER BY id").fetchall()
        return [dict(r) for r in rows]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `venv/Scripts/pytest tests/test_store.py -v`
Expected: 3 PASS

- [ ] **Step 5: Commit**

```bash
git add bot/store.py tests/test_store.py
git commit -m "feat: sqlite store for signals, orders, fills with dedup"
```

---

### Task 5: Risk guardrails

**Files:**
- Create: `bot/risk.py`
- Test: `tests/test_risk.py`

- [ ] **Step 1: Write the failing tests**

`tests/test_risk.py`:
```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `venv/Scripts/pytest tests/test_risk.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'bot.risk'`

- [ ] **Step 3: Write the implementation**

`bot/risk.py`:
```python
from datetime import datetime, time
from zoneinfo import ZoneInfo

ET = ZoneInfo("America/New_York")


def _parse_hhmm(s: str) -> time:
    h, m = s.split(":")
    return time(int(h), int(m))


class RiskManager:
    """Bot-side guardrails, enforced independently of Pine Script."""

    def __init__(self, settings):
        self.settings = settings
        self._day: str | None = None
        self._trades_today = 0
        self._realized_pnl = 0.0
        self._halted = False
        self._session_start = _parse_hhmm(settings.session_start)
        self._session_end = _parse_hhmm(settings.session_end)

    def _roll_day(self, now: datetime):
        day = now.astimezone(ET).date().isoformat()
        if day != self._day:
            self._day = day
            self._trades_today = 0
            self._realized_pnl = 0.0
            self._halted = False

    def check_entry(self, qty: int, now: datetime) -> tuple[bool, str]:
        self._roll_day(now)
        if self._halted:
            return False, "halted (kill switch or daily loss limit)"
        if qty > self.settings.qty:
            return False, f"max position is {self.settings.qty} contract(s)"
        if self._trades_today >= self.settings.max_trades_per_day:
            return False, f"max {self.settings.max_trades_per_day} trades/day reached"
        t = now.astimezone(ET).time()
        if not (self._session_start <= t <= self._session_end):
            return False, "outside trading hours 09:45-15:55 ET"
        if self._realized_pnl <= self.settings.daily_loss_limit:
            return False, "daily loss limit reached"
        return True, "ok"

    def record_entry(self, now: datetime):
        self._roll_day(now)
        self._trades_today += 1

    def record_pnl(self, pnl: float, now: datetime):
        self._roll_day(now)
        self._realized_pnl += pnl
        if self._realized_pnl <= self.settings.daily_loss_limit:
            self._halted = True

    def halt(self):
        self._halted = True

    @property
    def halted(self) -> bool:
        return self._halted
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `venv/Scripts/pytest tests/test_risk.py -v`
Expected: 7 PASS

- [ ] **Step 5: Commit**

```bash
git add bot/risk.py tests/test_risk.py
git commit -m "feat: risk guardrails - position, trade count, hours, loss limit, kill switch"
```

---

### Task 6: Tradovate API client

**Files:**
- Create: `bot/tradovate.py`
- Test: `tests/test_tradovate.py`

Note: endpoint shapes follow Tradovate's public API docs (https://api.tradovate.com). Verify field names against the docs during implementation if a request 400s in the dry run.

- [ ] **Step 1: Write the failing tests**

`tests/test_tradovate.py`:
```python
import httpx
import pytest

from bot.tradovate import TradovateClient


class FakeSettings:
    tradovate_api_url = "https://demo.tradovateapi.com/v1"
    tradovate_username = "u"
    tradovate_password = "p"
    tradovate_app_id = "app"
    tradovate_cid = "1"
    tradovate_sec = "sec"
    contract_symbol = "NQU6"
    qty = 1


def make_client(handler):
    transport = httpx.MockTransport(handler)
    http = httpx.AsyncClient(transport=transport,
                             base_url=FakeSettings.tradovate_api_url)
    return TradovateClient(FakeSettings(), http=http)


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
            import json
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
```

- [ ] **Step 2: Add pytest-asyncio config**

Append to a new file `pytest.ini` at project root:
```ini
[pytest]
asyncio_mode = auto
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `venv/Scripts/pytest tests/test_tradovate.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'bot.tradovate'`

- [ ] **Step 4: Write the implementation**

`bot/tradovate.py`:
```python
import httpx


class TradovateClient:
    """Minimal async client for Tradovate demo REST API."""

    def __init__(self, settings, http: httpx.AsyncClient | None = None):
        self.settings = settings
        self.http = http or httpx.AsyncClient(base_url=settings.tradovate_api_url)
        self.access_token: str | None = None
        self.account_id: int | None = None

    def _auth_headers(self) -> dict:
        return {"Authorization": f"Bearer {self.access_token}"}

    async def authenticate(self):
        r = await self.http.post("/auth/accesstokenrequest", json={
            "name": self.settings.tradovate_username,
            "password": self.settings.tradovate_password,
            "appId": self.settings.tradovate_app_id,
            "appVersion": "1.0",
            "cid": self.settings.tradovate_cid,
            "sec": self.settings.tradovate_sec,
        })
        r.raise_for_status()
        self.access_token = r.json()["accessToken"]

        r = await self.http.get("/account/list", headers=self._auth_headers())
        r.raise_for_status()
        accounts = r.json()
        if not accounts:
            raise RuntimeError("No Tradovate accounts found")
        self.account_id = accounts[0]["id"]

    async def place_bracket(self, action: str, qty: int,
                            stop: float, target: float) -> int:
        """Market entry with OSO bracket: protective stop + limit target."""
        exit_action = "Sell" if action == "buy" else "Buy"
        r = await self.http.post("/order/placeoso", headers=self._auth_headers(), json={
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
        r.raise_for_status()
        return r.json()["orderId"]

    async def modify_stop(self, order_id: int, new_stop: float):
        r = await self.http.post("/order/modifyorder", headers=self._auth_headers(),
                                 json={
                                     "orderId": order_id,
                                     "orderQty": self.settings.qty,
                                     "orderType": "Stop",
                                     "stopPrice": new_stop,
                                     "isAutomated": True,
                                 })
        r.raise_for_status()

    async def open_positions(self) -> list[dict]:
        r = await self.http.get("/position/list", headers=self._auth_headers())
        r.raise_for_status()
        return [p for p in r.json()
                if p.get("accountId") == self.account_id and p.get("netPos", 0) != 0]

    async def flatten_all(self) -> int:
        """Liquidate every open position. Returns count liquidated."""
        positions = await self.open_positions()
        for p in positions:
            r = await self.http.post("/order/liquidateposition",
                                     headers=self._auth_headers(), json={
                                         "accountId": self.account_id,
                                         "contractId": p["contractId"],
                                         "admin": False,
                                     })
            r.raise_for_status()
        return len(positions)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `venv/Scripts/pytest tests/test_tradovate.py -v`
Expected: 3 PASS

- [ ] **Step 6: Commit**

```bash
git add bot/tradovate.py tests/test_tradovate.py pytest.ini
git commit -m "feat: tradovate async client - auth, bracket orders, flatten"
```

---

### Task 7: FastAPI webhook server

**Files:**
- Create: `bot/main.py`
- Test: `tests/test_main.py`

- [ ] **Step 1: Write the failing tests**

`tests/test_main.py`:
```python
from datetime import datetime, timezone
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from bot.main import create_app


class FakeSettings:
    symbol = "NQ"
    qty = 1
    max_trades_per_day = 2
    daily_loss_limit = -1000.0
    session_start = "00:00"   # wide-open session so tests don't depend on clock
    session_end = "23:59"
    stale_seconds = 10
    db_path = ":memory:"
    webhook_secret = "s3cret"
    dry_run = False
    contract_symbol = "NQU6"


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
    app = create_app(FakeSettings(), broker=broker)
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
    from datetime import timedelta
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `venv/Scripts/pytest tests/test_main.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'bot.main'`

- [ ] **Step 3: Write the implementation**

`bot/main.py`:
```python
import json
import logging
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from fastapi import FastAPI, HTTPException, Request

from bot.models import Signal
from bot.risk import RiskManager
from bot.store import Store

log = logging.getLogger("bot")
ET = ZoneInfo("America/New_York")


def create_app(settings, broker) -> FastAPI:
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
        sig = Signal(**body)

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
                await broker.modify_stop(order_id, sig.stop)
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
    import uvicorn

    from bot.config import load_settings
    from bot.tradovate import TradovateClient

    logging.basicConfig(level=logging.INFO)
    settings = load_settings()
    broker = TradovateClient(settings)
    app = create_app(settings, broker)

    @app.on_event("startup")
    async def startup():
        if not settings.dry_run:
            await broker.authenticate()
            positions = await broker.open_positions()
            if positions:
                log.warning("Resuming with %d open position(s)", len(positions))

    uvicorn.run(app, host="127.0.0.1", port=8000)


if __name__ == "__main__":
    run()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `venv/Scripts/pytest tests/test_main.py -v`
Expected: 6 PASS

- [ ] **Step 5: Run the full suite**

Run: `venv/Scripts/pytest -v`
Expected: all tests PASS

- [ ] **Step 6: Commit**

```bash
git add bot/main.py tests/test_main.py
git commit -m "feat: fastapi webhook server with dedup, guardrails, kill switch"
```

---

### Task 8: Stats CLI

**Files:**
- Create: `bot/stats.py`
- Test: `tests/test_stats.py`

- [ ] **Step 1: Write the failing tests**

`tests/test_stats.py`:
```python
from bot.stats import compute_stats


def test_compute_stats_basic():
    fills = [
        {"signal_id": "a", "pnl": 400.0, "day": "2026-07-06"},
        {"signal_id": "b", "pnl": -200.0, "day": "2026-07-06"},
        {"signal_id": "c", "pnl": 600.0, "day": "2026-07-07"},
        {"signal_id": "d", "pnl": -200.0, "day": "2026-07-07"},
    ]
    s = compute_stats(fills)
    assert s["trades"] == 4
    assert s["win_rate"] == 0.5
    assert s["total_pnl"] == 600.0
    assert s["profit_factor"] == 2.5          # 1000 gross win / 400 gross loss
    assert s["pnl_by_day"]["2026-07-06"] == 200.0


def test_compute_stats_empty():
    s = compute_stats([])
    assert s["trades"] == 0
    assert s["total_pnl"] == 0.0


def test_max_drawdown():
    fills = [
        {"signal_id": "a", "pnl": 500.0, "day": "d1"},
        {"signal_id": "b", "pnl": -300.0, "day": "d1"},
        {"signal_id": "c", "pnl": -400.0, "day": "d2"},
        {"signal_id": "d", "pnl": 200.0, "day": "d2"},
    ]
    s = compute_stats(fills)
    assert s["max_drawdown"] == -700.0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `venv/Scripts/pytest tests/test_stats.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'bot.stats'`

- [ ] **Step 3: Write the implementation**

`bot/stats.py`:
```python
from collections import defaultdict


def compute_stats(fills: list[dict]) -> dict:
    """Stats over closed-trade fills (each dict has pnl and day).
    Zero-pnl fills (entries) are excluded from win/loss counts."""
    trades = [f for f in fills if f["pnl"] != 0.0]
    if not trades and not fills:
        return {"trades": 0, "win_rate": 0.0, "total_pnl": 0.0,
                "profit_factor": 0.0, "max_drawdown": 0.0, "pnl_by_day": {}}

    wins = [f["pnl"] for f in trades if f["pnl"] > 0]
    losses = [f["pnl"] for f in trades if f["pnl"] < 0]
    total = sum(f["pnl"] for f in trades)
    gross_win = sum(wins)
    gross_loss = abs(sum(losses))

    pnl_by_day: dict[str, float] = defaultdict(float)
    for f in trades:
        pnl_by_day[f["day"]] += f["pnl"]

    equity = 0.0
    peak = 0.0
    max_dd = 0.0
    for f in trades:
        equity += f["pnl"]
        peak = max(peak, equity)
        max_dd = min(max_dd, equity - peak)

    return {
        "trades": len(trades),
        "win_rate": len(wins) / len(trades) if trades else 0.0,
        "total_pnl": total,
        "profit_factor": gross_win / gross_loss if gross_loss else float("inf"),
        "max_drawdown": max_dd,
        "pnl_by_day": dict(pnl_by_day),
    }


def main():
    from bot.config import load_settings
    from bot.store import Store

    settings = load_settings()
    store = Store(settings.db_path)
    s = compute_stats(store.all_fills())
    print(f"Trades:        {s['trades']}")
    print(f"Win rate:      {s['win_rate']:.1%}")
    print(f"Total P&L:     ${s['total_pnl']:,.2f}")
    print(f"Profit factor: {s['profit_factor']:.2f}")
    print(f"Max drawdown:  ${s['max_drawdown']:,.2f}")
    print("P&L by day:")
    for day, pnl in sorted(s["pnl_by_day"].items()):
        print(f"  {day}: ${pnl:,.2f}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `venv/Scripts/pytest tests/test_stats.py -v`
Expected: 3 PASS

- [ ] **Step 5: Commit**

```bash
git add bot/stats.py tests/test_stats.py
git commit -m "feat: performance stats CLI - win rate, profit factor, drawdown"
```

---

### Task 9: Pine Script strategy

**Files:**
- Create: `pine/orb_sweep.pine`

No unit tests — this file is validated by TradingView's backtester (Validation Gate 1 in the spec). Paste into TradingView's Pine editor on an NQ 5-minute chart.

- [ ] **Step 1: Write the strategy**

`pine/orb_sweep.pine`:
```pine
//@version=5
strategy("ORB + Liquidity Sweep [NQ]", overlay=true,
     default_qty_type=strategy.fixed, default_qty_value=1,
     initial_capital=25000, commission_type=strategy.commission.cash_per_contract,
     commission_value=2.10, calc_on_every_tick=false)

// ── Inputs ──────────────────────────────────────────────────────────
orMinutes     = input.int(15, "Opening range minutes")
atrLen        = input.int(14, "ATR length")
volLen        = input.int(20, "Volume MA length")
maxTrades     = input.int(2, "Max trades per day")
rrTarget      = input.float(3.0, "Target R multiple")
beTriggerR    = input.float(1.5, "Breakeven trigger R")
webhookSecret = input.string("change-me", "Webhook secret")

// ── Session times (ET) ──────────────────────────────────────────────
inORWindow    = not na(time(timeframe.period, "0930-0945", "America/New_York"))
inEntryWindow = not na(time(timeframe.period, "0945-1130", "America/New_York"))
inSession     = not na(time(timeframe.period, "0945-1555", "America/New_York"))
atFlatTime    = not na(time(timeframe.period, "1555-1600", "America/New_York"))
newDay        = ta.change(time("D")) != 0

// ── Opening range ───────────────────────────────────────────────────
var float orHigh = na
var float orLow  = na
if newDay
    orHigh := na
    orLow := na
if inORWindow
    orHigh := na(orHigh) ? high : math.max(orHigh, high)
    orLow  := na(orLow)  ? low  : math.min(orLow, low)

// ── Liquidity levels ────────────────────────────────────────────────
var float priorDayHigh = na
var float priorDayLow  = na
var float overnightHigh = na
var float overnightLow  = na
var float trackHigh = na
var float trackLow  = na
inRTH = not na(time(timeframe.period, "0930-1600", "America/New_York"))

if newDay
    overnightHigh := trackHigh
    overnightLow  := trackLow
    trackHigh := na
    trackLow  := na
if inRTH
    // build prior-day RTH high/low
    trackHigh := na(trackHigh) ? high : math.max(trackHigh, high)
    trackLow  := na(trackLow)  ? low  : math.min(trackLow, low)
if ta.change(inRTH) < 0   // RTH just ended: freeze prior day levels
    priorDayHigh := trackHigh
    priorDayLow  := trackLow
    trackHigh := na          // reuse tracker for overnight
    trackLow  := na
if not inRTH
    trackHigh := na(trackHigh) ? high : math.max(trackHigh, high)
    trackLow  := na(trackLow)  ? low  : math.min(trackLow, low)

// ── Sweep detection ─────────────────────────────────────────────────
// A "sweep below" = price traded below a liquidity level today, then closed back above it.
var bool sweptBelow = false
var bool sweptAbove = false
if newDay
    sweptBelow := false
    sweptAbove := false

lowLiquidity  = math.min(nz(overnightLow, 1e10),  nz(priorDayLow, 1e10),  nz(orLow, 1e10))
highLiquidity = math.max(nz(overnightHigh, 0.0), nz(priorDayHigh, 0.0), nz(orHigh, 0.0))

if inSession and low < lowLiquidity and close > lowLiquidity
    sweptBelow := true
if inSession and high > highLiquidity and close < highLiquidity
    sweptAbove := true

// ── Entry conditions ────────────────────────────────────────────────
atr    = ta.atr(atrLen)
volOk  = volume > ta.sma(volume, volLen)
var int tradesToday = 0
if newDay
    tradesToday := 0

longBreak  = inEntryWindow and not na(orHigh) and close > orHigh and close[1] <= orHigh
shortBreak = inEntryWindow and not na(orLow)  and close < orLow  and close[1] >= orLow

canTrade  = tradesToday < maxTrades and strategy.position_size == 0
longEntry  = longBreak  and sweptBelow and volOk and canTrade
shortEntry = shortBreak and sweptAbove and volOk and canTrade

// ── Orders + alerts ─────────────────────────────────────────────────
orMid = (nz(orHigh) + nz(orLow)) / 2

f_payload(action, entryP, stopP, t1, t2) =>
    '{"secret":"' + webhookSecret + '","action":"' + action +
     '","symbol":"NQ","qty":1,"entry":' + str.tostring(entryP) +
     ',"stop":' + str.tostring(stopP) + ',"target1":' + str.tostring(t1) +
     ',"target2":' + str.tostring(t2) + ',"signal_id":"orb-' + action + '-' +
     str.tostring(time) + '","sent_at":"' + str.format_time(timenow,
     "yyyy-MM-dd'T'HH:mm:ssZ", "UTC") + '"}'

var float entryPrice = na
var float stopPrice  = na
var float t1Price    = na
var float t2Price    = na
var bool  beMoved    = false

if longEntry
    stopRaw    = close - atr
    stopPrice := math.max(stopRaw, orMid)   // cap at OR midpoint
    riskPts    = close - stopPrice
    t1Price   := close + beTriggerR * riskPts
    t2Price   := close + rrTarget * riskPts
    entryPrice := close
    beMoved   := false
    tradesToday += 1
    strategy.entry("L", strategy.long)
    strategy.exit("L-exit", "L", stop=stopPrice, limit=t2Price)
    alert(f_payload("buy", close, stopPrice, t1Price, t2Price), alert.freq_once_per_bar_close)

if shortEntry
    stopRaw    = close + atr
    stopPrice := math.min(stopRaw, orMid)
    riskPts    = stopPrice - close
    t1Price   := close - beTriggerR * riskPts
    t2Price   := close - rrTarget * riskPts
    entryPrice := close
    beMoved   := false
    tradesToday += 1
    strategy.entry("S", strategy.short)
    strategy.exit("S-exit", "S", stop=stopPrice, limit=t2Price)
    alert(f_payload("sell", close, stopPrice, t1Price, t2Price), alert.freq_once_per_bar_close)

// Breakeven move at 1.5R
longBE  = strategy.position_size > 0 and not beMoved and high >= t1Price
shortBE = strategy.position_size < 0 and not beMoved and low <= t1Price
if longBE or shortBE
    beMoved := true
    strategy.exit(strategy.position_size > 0 ? "L-exit" : "S-exit",
                 strategy.position_size > 0 ? "L" : "S",
                 stop=entryPrice, limit=t2Price)
    alert(f_payload("modify_stop", entryPrice, entryPrice, t1Price, t2Price),
         alert.freq_once_per_bar_close)

// Hard flat at 15:55
if atFlatTime and strategy.position_size != 0
    strategy.close_all("EOD flat")
    alert(f_payload("exit", close, 0, 0, 0), alert.freq_once_per_bar_close)

// ── Plots ───────────────────────────────────────────────────────────
plot(orHigh, "OR High", color=color.green, style=plot.style_linebr)
plot(orLow, "OR Low", color=color.red, style=plot.style_linebr)
plot(priorDayHigh, "PDH", color=color.gray, style=plot.style_linebr)
plot(priorDayLow, "PDL", color=color.gray, style=plot.style_linebr)
```

- [ ] **Step 2: Validate syntax**

Paste into TradingView Pine editor (NQ 5-min chart). Expected: compiles with no errors. Fix any version/syntax complaints inline — TradingView is the source of truth for Pine syntax.

- [ ] **Step 3: Commit**

```bash
git add pine/orb_sweep.pine
git commit -m "feat: ORB + liquidity sweep Pine strategy with webhook alerts"
```

---

### Task 10: Full suite + dry-run smoke test

**Files:**
- None created — verification only.

- [ ] **Step 1: Run the full test suite**

Run: `venv/Scripts/pytest -v`
Expected: all tests PASS (approx 22 tests).

- [ ] **Step 2: Dry-run smoke test**

Copy `.env.example` to `.env` (fill `WEBHOOK_SECRET=s3cret`, leave Tradovate creds blank, `DRY_RUN=1`).

Run: `venv/Scripts/python -m bot.main` (in background or second terminal)

Then:
```bash
curl -s -X POST http://127.0.0.1:8000/webhook -H "Content-Type: application/json" -d "{\"secret\":\"s3cret\",\"action\":\"buy\",\"symbol\":\"NQ\",\"qty\":1,\"entry\":21450.25,\"stop\":21418.5,\"target1\":21498.0,\"target2\":21545.75,\"signal_id\":\"smoke-1\",\"sent_at\":\"$(date -u +%Y-%m-%dT%H:%M:%S+00:00)\"}"
```
Expected: `{"status":"accepted","order_id":null}` if inside 9:45–15:55 ET, else `{"status":"rejected","reason":"outside trading hours..."}` — both prove the pipeline works.

Also: `curl -s http://127.0.0.1:8000/health` → `{"status":"ok","halted":false,"dry_run":true}`

- [ ] **Step 3: Verify stats CLI runs**

Run: `venv/Scripts/python -m bot.stats`
Expected: prints zeroed stats without error.

- [ ] **Step 4: Commit any fixes**

```bash
git add -u
git commit -m "test: dry-run smoke test fixes"
```
(Skip if nothing changed.)

---

## Post-implementation (manual, user-driven — not part of this plan)

1. Create Tradovate demo account + API credentials → fill `.env`.
2. TradingView Pro: add strategy to NQ 5-min chart, create alert with webhook URL from ngrok (`ngrok http 8000`), message = `{{strategy.order.alert_message}}`.
3. Validation Gate 1: backtest 6+ months in TradingView — positive expectancy required before wiring alerts.
4. Validation Gate 2: 1-week dry run (`DRY_RUN=1`).
5. Validation Gate 3: sim trading (`DRY_RUN=0`, demo account), 20+ trades / 4 weeks.

---

## Known limitations (V1)

- **No fill tracking → daily loss limit inactive.** Tradovate WebSocket fill
  tracking was descoped from V1, so `RiskManager.record_pnl()` is never called
  and `daily_loss_limit` never trips on its own. The `/halt` kill switch is the
  operative loss control; fill tracking is a V2 item.
- **`last_entry_order_id` is in-memory only.** A bot restart loses the active
  bracket order id, so `modify_stop` signals after a restart are rejected with
  "no active bracket order to modify" (safe failure mode). It is also cleared
  on `exit` and `/halt`.
- **Average R is not reported by the stats CLI.** Fills carry P&L only, not
  per-trade risk, so average R cannot be computed; stats also depend on fills
  being populated, which requires the V2 fill feed or manual entry.
- **RiskManager counters are in-memory.** A mid-day restart resets the
  trades-today count (2/day limit). The signals table retains the data needed
  to rebuild it if that ever matters.
