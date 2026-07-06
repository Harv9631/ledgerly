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


def test_all_zero_pnl_fills_returns_zero_stats():
    fills = [
        {"signal_id": "a", "pnl": 0.0, "day": "2026-07-06"},
        {"signal_id": "b", "pnl": 0.0, "day": "2026-07-06"},
    ]
    s = compute_stats(fills)
    assert s == {
        "trades": 0,
        "win_rate": 0.0,
        "total_pnl": 0.0,
        "profit_factor": 0.0,
        "max_drawdown": 0.0,
        "pnl_by_day": {},
    }
