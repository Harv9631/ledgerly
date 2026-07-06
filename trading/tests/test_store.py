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
