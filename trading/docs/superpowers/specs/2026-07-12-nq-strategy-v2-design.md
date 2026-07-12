# NQ Strategy V2 — Refined ORB + IB Single-Break with SMT Divergence Filter — Design Spec

**Date:** 2026-07-12
**Status:** Approved by user (design review complete)
**Scope:** Pine Script only. The Python bot (`bot/`) is unchanged — both strategies emit
the identical webhook payload defined in the V1 spec (`2026-07-05-nq-orb-sweep-bot-design.md`).
The existing `pine/orb_sweep.pine` is kept for reference and is NOT modified.

## Purpose

The V1 ORB + liquidity-sweep strategy failed its TradingView backtest gate. Replace it
with two mechanical candidates that have the strongest published structural stats for NQ,
plus an optional SMT-divergence filter (true divergence, per user choice "B"). The two
strategies are backtested head-to-head; whichever passes the validation gate gets wired
to the bot.

## Files

- Create: `pine/orb_v2.pine` — Refined ORB (one trade/day, 50%-range target)
- Create: `pine/ib_break.pine` — Initial Balance single-break
- Unchanged: `pine/orb_sweep.pine`, all of `bot/`, `tests/`, `config/`

## Shared Conventions (both strategies)

- Pine Script v5, `strategy()` with `process_orders_on_close=true`,
  `calc_on_every_tick=false` (non-repainting; entries on confirmed bar closes only).
- Chart requirement: NQ (e.g. `CME_MINI:NQ1!`), **5-minute**, **ETH session** —
  header comment enforces this, as in V1.
- All times ET via `timestamp("America/New_York", ...)`-safe session logic
  (same session-anchoring pattern as V1: RTH transitions, not calendar-day resets).
- Continuation-line indentation must NOT be a multiple of 4 (Pine compiler rule; V1
  uses 17 spaces).
- Alerts: `alert.freq_once_per_bar_close`, JSON payload identical to V1 schema:

```json
{
  "secret": "{{secret placeholder — user pastes real value in alert dialog}}",
  "action": "buy" | "sell" | "exit",
  "symbol": "NQ",
  "qty": 1,
  "entry": <float>,
  "stop": <float>,
  "target1": <float>,
  "target2": <float>,
  "signal_id": "<strategy>-<side>-<yyyy-mm-dd>",
  "sent_at": "<UTC ISO8601 with literal Z>"
}
```

  Both strategies are single-target: `target1 == target2` (bot requires `target2 > 0`).
- One trade per day (a single entry attempt; once a trade has been opened that day,
  no further entries).
- Hard flat at 15:55 ET: close any open position and fire an `exit` alert.
- Position size: 1 contract.

## Strategy 1: `orb_v2.pine` — Refined ORB

- **Opening range:** 9:30–9:45 ET high/low (15 minutes, 3 five-minute bars).
- **Entry window:** after 9:45, before 11:30 ET.
- **Long:** first 5-minute candle that CLOSES above OR high → buy at that close.
- **Short:** first 5-minute candle that CLOSES below OR low → sell at that close.
- **Stop:** opposite side of the opening range (long stop = OR low, short stop = OR high).
- **Target:** `targetPct` × OR size beyond the entry close, where OR size = OR high − OR low.
  `targetPct` is an input, default `0.5`, range 0.25–1.0 step 0.05.
- First triggered side takes the day's one trade; no re-entry, no second side.

## Strategy 2: `ib_break.pine` — Initial Balance Single-Break

- **Initial balance:** 9:30–10:30 ET high/low (12 five-minute bars).
- **Entry window:** after 10:30, before 13:00 ET.
- **Long:** first 5-minute candle that CLOSES above IB high → buy at that close.
- **Short:** first 5-minute candle that CLOSES below IB low → sell at that close.
- **Stop:** opposite IB extreme (long stop = IB low, short stop = IB high). This is the
  level the ~82% single-break statistic protects.
- **Target:** `targetPct` × IB width beyond the entry close. Input, default `0.5`,
  range 0.25–1.0 step 0.05.
- **First-hour direction filter** (input toggle `useFirstHourFilter`, default ON):
  only take breaks in the same direction as the 9:30–10:30 hour's net candle
  (close at 10:30 vs. open at 9:30). Bullish first hour → longs only; bearish → shorts
  only; flat (equal) → both allowed.
- One trade per day, as above.

## SMT Divergence Filter (input toggle in BOTH files, default OFF)

True SMT divergence (user choice B): a sweep in NQ that ES refuses to confirm marks the
prior move as a liquidity grab, supporting entry in the opposite direction.

**Reference levels:** each strategy's own range levels — OR high/low for `orb_v2`,
IB high/low for `ib_break`. ES's corresponding range is computed from
`request.security("CME_MINI:ES1!", timeframe.period, ...)` with
`lookahead=barmerge.lookahead_off` on confirmed bars, using the same session windows.

**Bullish SMT (required for LONG entries when filter is ON):**
On some bar after the range completes and at-or-before the entry bar, NQ's low traded
below its range low while ES's low on that same bar stayed at-or-above ES's own range
low. Latch a `bullSMT` flag when this occurs; reset daily.

**Bearish SMT (required for SHORT entries):** mirror — NQ's high above its range high
while ES's high stays at-or-below ES's range high on the same bar.

**Notes:**
- The divergence bar itself cannot also be the entry bar for the same side (the entry
  candle must CLOSE beyond the range in the trade direction; a bullish-SMT bar by
  definition traded below the range low — these are distinct events on 5-minute bars,
  but if both conditions ever coincide on one bar, the entry takes precedence and the
  latch is not required to have been set on an earlier bar; implementation: evaluate
  SMT latch before entry check within the bar).
- `na` guards: if ES data is unavailable on a bar, no SMT latch can be set that bar.
- Toggling the filter gives 4 backtest combos across the 2 files (8 with the
  first-hour filter on `ib_break`).

## Error Handling / Edge Cases

- Day with OR/IB size of 0 (flat range): no trades that day (target would be 0 wide).
- Entry candle gaps far beyond the range: entry is still the candle close; stop remains
  the opposite range extreme (risk grows — acceptable; backtest will price it).
- Early-close/holiday sessions: hard-flat logic also fires if the session ends before
  15:55 (position closed by `strategy.close_all` guard on last bar of session).
- No overnight positions ever.

## Testing / Validation

Pine has no local unit tests. Validation is the V1 gate applied per candidate:

1. TradingView Strategy Tester, NQ 5-min ETH, 6+ months, commission $2.50/side/contract,
   slippage 1 tick.
2. Backtest matrix: `orb_v2` × {SMT on, off}; `ib_break` × {SMT on, off} ×
   {first-hour filter on, off}.
3. Pass criteria (per V1): positive net profit after costs, profit factor > 1.2,
   ≥ 50 trades, tolerable max drawdown, long/short not wildly lopsided.
4. Trade-list sanity check: entry windows respected, flat by 15:55, one trade/day.
5. Only a passing candidate proceeds to alert wiring (bot unchanged; Validation Gates
   2–3 from V1 then apply).

## Out of Scope

- Any change to `bot/`, `config/`, `tests/`, or the webhook contract.
- Live trading (V1 rule stands: demo only).
- Kane's discretionary elements (premium/discount zones, iFVG entries, "A+ setup"
  judgment) — only the mechanical SMT divergence concept is adopted.
