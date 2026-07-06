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
    def _action_price_requirements(self) -> "Signal":
        if self.action == "modify_stop" and self.stop <= 0:
            raise ValueError("modify_stop requires a positive stop price")
        if self.action in ("buy", "sell"):
            if self.stop <= 0:
                raise ValueError("entry requires a positive stop price")
            if self.target2 <= 0:
                raise ValueError("entry requires a positive target2 price")
        return self

    def age_seconds(self, now: datetime | None = None) -> float:
        now = now or datetime.now(timezone.utc)
        sent = self.sent_at
        if sent.tzinfo is None:
            sent = sent.replace(tzinfo=timezone.utc)
        return (now - sent).total_seconds()
