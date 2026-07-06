from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel


class Signal(BaseModel):
    secret: str
    action: Literal["buy", "sell", "exit", "modify_stop"]
    symbol: str
    qty: int = 1
    entry: float = 0.0
    stop: float = 0.0
    target1: float = 0.0
    target2: float = 0.0
    signal_id: str
    sent_at: datetime

    def age_seconds(self, now: datetime | None = None) -> float:
        now = now or datetime.now(timezone.utc)
        sent = self.sent_at
        if sent.tzinfo is None:
            sent = sent.replace(tzinfo=timezone.utc)
        return (now - sent).total_seconds()
