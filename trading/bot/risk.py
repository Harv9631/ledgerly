from datetime import datetime, time
from zoneinfo import ZoneInfo

from bot.config import Settings

ET = ZoneInfo("America/New_York")


def _parse_hhmm(s: str) -> time:
    h, m = s.split(":")
    return time(int(h), int(m))


class RiskManager:
    """Bot-side guardrails, enforced independently of Pine Script."""

    def __init__(self, settings: Settings):
        self.settings = settings
        self._day: str | None = None
        self._trades_today = 0
        self._realized_pnl = 0.0
        self._halted = False
        self._session_start = _parse_hhmm(settings.session_start)
        self._session_end = _parse_hhmm(settings.session_end)

    def _roll_day(self, now: datetime):
        if now.tzinfo is None:
            raise ValueError("now must be timezone-aware, got a naive datetime")
        day = now.astimezone(ET).date().isoformat()
        if day != self._day:
            is_rollover = self._day is not None
            self._day = day
            self._trades_today = 0
            self._realized_pnl = 0.0
            if is_rollover:
                self._halted = False

    def check_entry(self, qty: int, now: datetime) -> tuple[bool, str]:
        self._roll_day(now)
        if self._halted:
            return False, "halted (kill switch or daily loss limit)"
        if qty > self.settings.max_contracts:
            return False, f"max position is {self.settings.max_contracts} contract(s)"
        if self._trades_today >= self.settings.max_trades_per_day:
            return False, f"max {self.settings.max_trades_per_day} trades/day reached"
        t = now.astimezone(ET).time()
        if not (self._session_start <= t <= self._session_end):
            return False, (
                f"outside trading hours {self.settings.session_start}-"
                f"{self.settings.session_end} ET"
            )
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
