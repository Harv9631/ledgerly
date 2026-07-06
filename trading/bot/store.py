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
