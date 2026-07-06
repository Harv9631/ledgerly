from collections import defaultdict


def compute_stats(fills: list[dict]) -> dict:
    """Stats over closed-trade fills (each dict has pnl and day).
    Zero-pnl fills (entries) are excluded from win/loss counts."""
    trades = [f for f in fills if f["pnl"] != 0.0]
    if not trades:
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
        "win_rate": len(wins) / len(trades),
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
