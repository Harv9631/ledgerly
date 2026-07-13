# NQ Strategy V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two backtest-candidate Pine strategies for NQ — refined ORB and IB single-break — each with an optional SMT-divergence filter, emitting the existing bot webhook payload.

**Architecture:** Pine Script v5 only; the Python bot is untouched. Both files follow the proven patterns from `pine/orb_sweep.pine`: RTH-anchored session resets, close-confirmed non-repainting entries, raw-JSON alert payloads. ES data for SMT comes from `request.security` with lookahead off.

**Tech Stack:** Pine Script v5, TradingView Strategy Tester (validation).

**Spec:** `docs/superpowers/specs/2026-07-12-nq-strategy-v2-design.md`

---

## Critical Pine constraints (apply to BOTH tasks)

1. **Continuation-line indentation must NOT be a multiple of 4 spaces** or Pine fails to compile. Use 5 spaces for wrapped lines (matches `orb_sweep.pine` style).
2. Non-repainting: `calc_on_every_tick=false`, `process_orders_on_close=true`, entries only on confirmed bar closes, `alert.freq_once_per_bar_close`.
3. `request.security` MUST use `lookahead=barmerge.lookahead_off`.
4. No local test runner exists for Pine. Verification = file content review + user pastes into TradingView Pine Editor (compile check is manual, done by the user after both tasks).
5. Header comment must state the ETH-chart requirement.

---

### Task 1: `pine/orb_v2.pine` — Refined ORB

**Files:**
- Create: `pine/orb_v2.pine`

- [ ] **Step 1: Write the file with exactly this content**

```pine
//@version=5
// NOTE: Requires an ETH (24h) chart of NQ on the 5-minute timeframe (e.g. CME_MINI:NQ1!).
// The SMT filter pulls CME_MINI:ES1! data; RTH-only charts break session anchoring.
strategy("ORB v2 [NQ]", overlay=true,
     default_qty_type=strategy.fixed, default_qty_value=1,
     initial_capital=25000, commission_type=strategy.commission.cash_per_contract,
     commission_value=2.10, calc_on_every_tick=false, process_orders_on_close=true)

// ── Inputs ──────────────────────────────────────────────────────────
targetPct     = input.float(0.5, "Target (fraction of OR size)", minval=0.25, maxval=1.0, step=0.05)
useSMT        = input.bool(false, "Require SMT divergence (ES non-confirmation)")
esSymbol      = input.symbol("CME_MINI:ES1!", "SMT comparison symbol")
// Secret must not contain quotes or backslashes (payload is built by raw JSON string concatenation).
webhookSecret = input.string("change-me", "Webhook secret")

// ── Session times (ET) ──────────────────────────────────────────────
inORWindow    = not na(time(timeframe.period, "0930-0945", "America/New_York"))
inEntryWindow = not na(time(timeframe.period, "0945-1130", "America/New_York"))
atFlatTime    = not na(time(timeframe.period, "1550-1555", "America/New_York"))
inRTH         = not na(time(timeframe.period, "0930-1600", "America/New_York"))
rthStart      = inRTH and not inRTH[1]   // 9:30 ET — daily resets anchored here

// ── Opening range (NQ) ──────────────────────────────────────────────
var float orHigh = na
var float orLow  = na
if rthStart
    orHigh := na
    orLow  := na
if inORWindow
    orHigh := na(orHigh) ? high : math.max(orHigh, high)
    orLow  := na(orLow)  ? low  : math.min(orLow, low)
orSize = orHigh - orLow   // na until both legs exist

// ── ES data + ES opening range (for SMT) ────────────────────────────
[esHigh, esLow] = request.security(esSymbol, timeframe.period, [high, low],
     gaps=barmerge.gaps_on, lookahead=barmerge.lookahead_off)
var float esOrHigh = na
var float esOrLow  = na
if rthStart
    esOrHigh := na
    esOrLow  := na
if inORWindow and not na(esHigh)
    esOrHigh := na(esOrHigh) ? esHigh : math.max(esOrHigh, esHigh)
    esOrLow  := na(esOrLow)  ? esLow  : math.min(esOrLow, esLow)

// ── SMT divergence latches (evaluated BEFORE entry checks) ──────────
// Bullish SMT: NQ trades below its OR low while ES holds at/above its own OR low.
var bool bullSMT = false
var bool bearSMT = false
if rthStart
    bullSMT := false
    bearSMT := false
if inEntryWindow and not na(orLow) and not na(esOrLow) and not na(esLow)
    if low < orLow and esLow >= esOrLow
        bullSMT := true
if inEntryWindow and not na(orHigh) and not na(esOrHigh) and not na(esHigh)
    if high > orHigh and esHigh <= esOrHigh
        bearSMT := true

// ── Entry conditions (one trade per day, first side to trigger) ─────
var bool tradeUsed = false
if rthStart
    tradeUsed := false

rangeOk    = not na(orSize) and orSize > 0
canTrade   = not tradeUsed and strategy.position_size == 0 and not session.islastbar_regular
smtOkLong  = not useSMT or bullSMT
smtOkShort = not useSMT or bearSMT

// With SMT on, a rejected first breakout close (SMT not yet latched) means no entry until price re-crosses the level — intentional "first confirmed break or nothing" behavior.
longBreak  = inEntryWindow and rangeOk and close > orHigh and close[1] <= orHigh
shortBreak = inEntryWindow and rangeOk and close < orLow  and close[1] >= orLow

longEntry  = longBreak  and canTrade and smtOkLong
shortEntry = shortBreak and canTrade and smtOkShort

// ── Payload helper ──────────────────────────────────────────────────
f_payload(action, entryP, stopP, t1, t2) =>
    '{"secret":"' + webhookSecret + '","action":"' + action +
     '","symbol":"NQ","qty":1,"entry":' + str.tostring(entryP) +
     ',"stop":' + str.tostring(stopP) + ',"target1":' + str.tostring(t1) +
     ',"target2":' + str.tostring(t2) + ',"signal_id":"orbv2-' + action + '-' +
     str.tostring(time) + '","sent_at":"' + str.format_time(timenow,
     "yyyy-MM-dd'T'HH:mm:ss'Z'", "UTC") + '"}'

// ── Orders + alerts ─────────────────────────────────────────────────
if longEntry
    stopP = orLow
    tgt   = close + targetPct * orSize
    tradeUsed := true
    strategy.entry("L", strategy.long)
    strategy.exit("L-exit", "L", stop=stopP, limit=tgt)
    alert(f_payload("buy", close, stopP, tgt, tgt), alert.freq_once_per_bar_close)

if shortEntry
    stopP = orHigh
    tgt   = close - targetPct * orSize
    tradeUsed := true
    strategy.entry("S", strategy.short)
    strategy.exit("S-exit", "S", stop=stopP, limit=tgt)
    alert(f_payload("sell", close, stopP, tgt, tgt), alert.freq_once_per_bar_close)

// ── Hard flat at 15:55 (+ safety net: close on last regular-session bar; covers early closes) ──────
if atFlatTime and strategy.position_size != 0
    strategy.close_all("EOD flat")
    alert(f_payload("exit", close, 0, 0, 0), alert.freq_once_per_bar_close)
if session.islastbar_regular and strategy.position_size != 0
    strategy.close_all("Session end flat")
    alert(f_payload("exit", close, 0, 0, 0), alert.freq_once_per_bar_close)

// ── Plots ───────────────────────────────────────────────────────────
plot(orHigh, "OR High", color=color.green, style=plot.style_linebr)
plot(orLow,  "OR Low",  color=color.red,   style=plot.style_linebr)
bgcolor(useSMT and bullSMT and inEntryWindow ? color.new(color.green, 92) : na)
bgcolor(useSMT and bearSMT and inEntryWindow ? color.new(color.red, 92) : na)
```

- [ ] **Step 2: Verify continuation-line indentation**

Visually confirm every wrapped continuation line (inside `strategy(...)`, `request.security(...)`, `f_payload`, `alert(...)`) starts with exactly 5 spaces — never 4, 8, 12, or 16.

- [ ] **Step 3: Commit**

```bash
cd /c/Users/harve && git add trading/pine/orb_v2.pine && git commit -m "feat: ORB v2 pine strategy - 50%-range target, one trade/day, SMT toggle"
```

---

### Task 2: `pine/ib_break.pine` — Initial Balance Single-Break

**Files:**
- Create: `pine/ib_break.pine`

- [ ] **Step 1: Write the file with exactly this content**

```pine
//@version=5
// NOTE: Requires an ETH (24h) chart of NQ on the 5-minute timeframe (e.g. CME_MINI:NQ1!).
// The SMT filter pulls CME_MINI:ES1! data; RTH-only charts break session anchoring.
strategy("IB Single-Break [NQ]", overlay=true,
     default_qty_type=strategy.fixed, default_qty_value=1,
     initial_capital=25000, commission_type=strategy.commission.cash_per_contract,
     commission_value=2.10, calc_on_every_tick=false, process_orders_on_close=true)

// ── Inputs ──────────────────────────────────────────────────────────
targetPct     = input.float(0.5, "Target (fraction of IB width)", minval=0.25, maxval=1.0, step=0.05)
useFH         = input.bool(true, "First-hour direction filter")
useSMT        = input.bool(false, "Require SMT divergence (ES non-confirmation)")
esSymbol      = input.symbol("CME_MINI:ES1!", "SMT comparison symbol")
// Secret must not contain quotes or backslashes (payload is built by raw JSON string concatenation).
webhookSecret = input.string("change-me", "Webhook secret")

// ── Session times (ET) ──────────────────────────────────────────────
inIBWindow    = not na(time(timeframe.period, "0930-1030", "America/New_York"))
inEntryWindow = not na(time(timeframe.period, "1030-1300", "America/New_York"))
atFlatTime    = not na(time(timeframe.period, "1550-1555", "America/New_York"))
inRTH         = not na(time(timeframe.period, "0930-1600", "America/New_York"))
rthStart      = inRTH and not inRTH[1]   // 9:30 ET — daily resets anchored here

// ── Initial balance (NQ) ────────────────────────────────────────────
var float ibHigh = na
var float ibLow  = na
if rthStart
    ibHigh := na
    ibLow  := na
if inIBWindow
    ibHigh := na(ibHigh) ? high : math.max(ibHigh, high)
    ibLow  := na(ibLow)  ? low  : math.min(ibLow, low)
ibWidth = ibHigh - ibLow   // na until both legs exist

// ── First-hour direction (9:30 open vs 10:30 close) ─────────────────
var float dayOpen = na
var int   fhDir   = 0
if rthStart
    dayOpen := open
    fhDir   := 0
ibJustEnded = not inIBWindow and inIBWindow[1]
if ibJustEnded and not na(dayOpen)
    fhDir := close[1] > dayOpen ? 1 : close[1] < dayOpen ? -1 : 0

// ── ES data + ES initial balance (for SMT) ──────────────────────────
[esHigh, esLow] = request.security(esSymbol, timeframe.period, [high, low],
     gaps=barmerge.gaps_on, lookahead=barmerge.lookahead_off)
var float esIbHigh = na
var float esIbLow  = na
if rthStart
    esIbHigh := na
    esIbLow  := na
if inIBWindow and not na(esHigh)
    esIbHigh := na(esIbHigh) ? esHigh : math.max(esIbHigh, esHigh)
    esIbLow  := na(esIbLow)  ? esLow  : math.min(esIbLow, esLow)

// ── SMT divergence latches (evaluated BEFORE entry checks) ──────────
// Bullish SMT: NQ trades below its IB low while ES holds at/above its own IB low.
var bool bullSMT = false
var bool bearSMT = false
if rthStart
    bullSMT := false
    bearSMT := false
if inEntryWindow and not na(ibLow) and not na(esIbLow) and not na(esLow)
    if low < ibLow and esLow >= esIbLow
        bullSMT := true
if inEntryWindow and not na(ibHigh) and not na(esIbHigh) and not na(esHigh)
    if high > ibHigh and esHigh <= esIbHigh
        bearSMT := true

// ── Entry conditions (one trade per day, first side to trigger) ─────
var bool tradeUsed = false
if rthStart
    tradeUsed := false

rangeOk    = not na(ibWidth) and ibWidth > 0
canTrade   = not tradeUsed and strategy.position_size == 0 and not session.islastbar_regular
smtOkLong  = not useSMT or bullSMT
smtOkShort = not useSMT or bearSMT
fhOkLong   = not useFH or fhDir >= 0
fhOkShort  = not useFH or fhDir <= 0

// With SMT on, a rejected first breakout close (SMT not yet latched) means no entry until price re-crosses the level — intentional "first confirmed break or nothing" behavior.
longBreak  = inEntryWindow and rangeOk and close > ibHigh and close[1] <= ibHigh
shortBreak = inEntryWindow and rangeOk and close < ibLow  and close[1] >= ibLow

longEntry  = longBreak  and canTrade and smtOkLong  and fhOkLong
shortEntry = shortBreak and canTrade and smtOkShort and fhOkShort

// ── Payload helper ──────────────────────────────────────────────────
f_payload(action, entryP, stopP, t1, t2) =>
    '{"secret":"' + webhookSecret + '","action":"' + action +
     '","symbol":"NQ","qty":1,"entry":' + str.tostring(entryP) +
     ',"stop":' + str.tostring(stopP) + ',"target1":' + str.tostring(t1) +
     ',"target2":' + str.tostring(t2) + ',"signal_id":"ibbrk-' + action + '-' +
     str.tostring(time) + '","sent_at":"' + str.format_time(timenow,
     "yyyy-MM-dd'T'HH:mm:ss'Z'", "UTC") + '"}'

// ── Orders + alerts ─────────────────────────────────────────────────
if longEntry
    stopP = ibLow
    tgt   = close + targetPct * ibWidth
    tradeUsed := true
    strategy.entry("L", strategy.long)
    strategy.exit("L-exit", "L", stop=stopP, limit=tgt)
    alert(f_payload("buy", close, stopP, tgt, tgt), alert.freq_once_per_bar_close)

if shortEntry
    stopP = ibHigh
    tgt   = close - targetPct * ibWidth
    tradeUsed := true
    strategy.entry("S", strategy.short)
    strategy.exit("S-exit", "S", stop=stopP, limit=tgt)
    alert(f_payload("sell", close, stopP, tgt, tgt), alert.freq_once_per_bar_close)

// ── Hard flat at 15:55 (+ safety net: close on last regular-session bar; covers early closes) ──────
if atFlatTime and strategy.position_size != 0
    strategy.close_all("EOD flat")
    alert(f_payload("exit", close, 0, 0, 0), alert.freq_once_per_bar_close)
if session.islastbar_regular and strategy.position_size != 0
    strategy.close_all("Session end flat")
    alert(f_payload("exit", close, 0, 0, 0), alert.freq_once_per_bar_close)

// ── Plots ───────────────────────────────────────────────────────────
plot(ibHigh, "IB High", color=color.green, style=plot.style_linebr)
plot(ibLow,  "IB Low",  color=color.red,   style=plot.style_linebr)
bgcolor(useSMT and bullSMT and inEntryWindow ? color.new(color.green, 92) : na)
bgcolor(useSMT and bearSMT and inEntryWindow ? color.new(color.red, 92) : na)
```

- [ ] **Step 2: Verify continuation-line indentation**

Same check as Task 1 Step 2 — every wrapped continuation line starts with exactly 5 spaces.

- [ ] **Step 3: Commit**

```bash
cd /c/Users/harve && git add trading/pine/ib_break.pine && git commit -m "feat: IB single-break pine strategy - first-hour filter, SMT toggle"
```

---

### Task 3: Manual TradingView validation (user-executed, not agent work)

- [ ] Paste each file into TradingView Pine Editor on an NQ 5-min ETH chart; both must compile clean
- [ ] Strategy Tester settings: commission $2.50/side/contract, slippage 1 tick, 6+ months
- [ ] Run the backtest matrix: `orb_v2` × {SMT on/off}; `ib_break` × {SMT on/off} × {first-hour on/off}
- [ ] Trade-list sanity per combo: entries only in the entry window, flat by 15:55, one trade/day
- [ ] Pass gate: net positive after costs, profit factor > 1.2, ≥ 50 trades, tolerable drawdown
- [ ] Record results (screenshot Performance Summary + settings) before any parameter tweaks
