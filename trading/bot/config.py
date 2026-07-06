import os
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

import yaml
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SETTINGS_YAML = PROJECT_ROOT / "config" / "settings.yaml"


@dataclass(frozen=True)
class Settings:
    symbol: str
    qty: int
    max_contracts: int
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
    if urlparse(api_url).hostname != "demo.tradovateapi.com":
        raise RuntimeError(
            "V1 supports DEMO accounts only. TRADOVATE_API_URL must point at "
            "demo.tradovateapi.com. Refusing to start."
        )

    raw_dry_run = os.environ.get("DRY_RUN", "1").strip().lower()
    if raw_dry_run in ("1", "true", "yes"):
        dry_run = True
    elif raw_dry_run in ("0", "false", "no"):
        dry_run = False
    else:
        raise RuntimeError(f"DRY_RUN must be a boolean-like value, got: {raw_dry_run!r}")

    return Settings(
        symbol=y["symbol"],
        qty=int(y["qty"]),
        max_contracts=int(y["max_contracts"]),
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
        dry_run=dry_run,
    )
