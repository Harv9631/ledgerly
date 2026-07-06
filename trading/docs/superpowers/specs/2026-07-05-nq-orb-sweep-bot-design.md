# NQ ORB + Liquidity Sweep Trading Bot — Design Spec

**Date:** 2026-07-05
**Status:** Approved by user (design review complete)
**Scope:** V1 — simulation trading only. Live trading is explicitly out of scope.

## Purpose

Automate an Opening Range Breakout (ORB) strategy with liquidity-sweep confirmation
on NQ (E-mini Nasdaq-100 futures). TradingView Pine Script generates signals;
a local Python bot executes them against a Tradovate DEMO account. The goal of V1
is to validate the full pipeline and measure the strategy's real performance in sim.

## Architecture

```
TradingView (Pine Script strategy on NQ chart)
    │  alert fires with JSON payload
    ▼
ngrok tunnel ──> FastAPI server (Python, local PC)
    │  validates signal, applies risk guardrails
    ▼
Tradovate REST/WebSocket API (DEMO account only)
    │  places bracket order (entry + stop + target)
    ▼
Trade log (SQLite) ──> stats CLI (win rate, R, drawdown)
```

**Separation of concerns:**
- Pine Script owns ALL strategy logic (entries, exits, filters).
- The Python bot owns execution and safety. It never originates trades; it only
  executes or rejects signals from Pine.

## Strategy Rules (Pine Script)

Instrument: NQ (full size, $20/point). Session: RTH, all times ET.

### Setup phase (9:30–9:45)
- Record 15-minute opening range: OR high, OR low.
- Track liquidity levels: overnight high/low, prior day high/low,
  pre-market swing points.

### Long entry — ALL conditions required
1. Price breaks above OR high after 9:45.
2. Sweep condition: before the breakout, price swept a liquidity level below
   (took out overnight low or prior-day low then reclaimed), OR the OR low was
   swept and price reversed up through the range.
3. Breakout candle CLOSES above OR high (no wick-only triggers).
4. Breakout candle volume > 20-bar average volume.
5. Time is before 11:30 (no new entries after).

### Short entry
Mirror image of long entry.

### Exits
- Stop: 1x ATR(14) below entry, capped at OR midpoint.
- Target 1: 1.5R — exit half position, move stop to breakeven.
- Target 2: 3R or nearest opposing liquidity level, whichever is closer.
- Hard flat at 15:55 — no overnight positions.
- Max 2 trades/day (one long attempt, one short attempt).

## Webhook Payload (TradingView → bot)

```json
{
  "secret": "<shared token>",
  "action": "buy" | "sell" | "exit",
  "symbol": "NQ",
  "qty": 1,
  "entry": 21450.25,
  "stop": 21418.50,
  "target1": 21498.00,
  "target2": 21545.75,
  "signal_id": "orb-sweep-long-2026-07-06"
}
```

## Python Bot (FastAPI)

- **Auth:** reject any request lacking the shared secret. ngrok URL kept private.
- **Dedup:** ignore duplicate `signal_id` values (TradingView can re-fire alerts).
- **Orders:** Tradovate bracket order (entry + OCO stop/target) on the DEMO
  account only. Account ID is configured to demo; the bot refuses to start if
  configured with a live account in V1.
- **State:** WebSocket subscription to fills/positions — the bot tracks actual
  broker state, never assumed state.

## Risk Guardrails (bot-side, independent of Pine)

| Guardrail | Rule |
|---|---|
| Max position | 1 NQ contract |
| Max trades/day | 2, enforced by bot even if Pine misfires |
| Daily loss limit | Flatten and halt after -$1,000 realized on the day |
| Trading hours | Reject signals outside 9:45–15:55 ET |
| Kill switch | `POST /halt` endpoint; Ctrl-C flattens positions before shutdown |
| Stale signals | Reject alerts with timestamp older than 10 seconds |

## Trade Logging & Stats

SQLite records every signal (accepted/rejected with reason), order, and fill.
A `stats` CLI command reports: win rate, average R, profit factor, max drawdown,
and P&L by day.

## Validation Gates (sequential)

1. **Backtest:** Pine strategy over 6+ months of NQ 5-minute data in TradingView.
   Must show positive expectancy before any wiring.
2. **Dry run:** webhook → bot with order placement mocked (log-only), 1 week.
3. **Sim trading:** Tradovate demo, minimum 20 trades / 4 weeks.
4. **Live:** out of scope for V1. The bot deliberately does not support live
   accounts. Going live is a separate future decision by the user.

## Project Structure

```
trading/
├── pine/orb_sweep.pine          # TradingView strategy
├── bot/
│   ├── main.py                  # FastAPI app + webhook endpoint
│   ├── tradovate.py             # API client (auth, orders, websocket)
│   ├── risk.py                  # guardrails
│   ├── store.py                 # SQLite logging
│   └── stats.py                 # performance report CLI
├── config/settings.yaml         # references env vars; secrets live in .env
└── tests/                       # unit tests with mocked Tradovate client
```

## Tech Stack & Prerequisites

- Python 3.11+, FastAPI, uvicorn, httpx, websockets, SQLite (stdlib sqlite3).
- TradingView Pro plan (required for webhook alerts).
- Tradovate demo account (free) with API access credentials.
- ngrok (free tier, static domain) tunneling to the local FastAPI server.
- Secrets (Tradovate credentials, webhook shared secret) in `.env`, never committed.

## Error Handling

- Tradovate API failure on order placement: log, alert loudly in console, do not
  retry entries (a missed trade is safer than a duplicate).
- WebSocket disconnect: reconnect with backoff; while state is unknown, reject
  new signals.
- Bot restart mid-position: on startup, query broker for open positions and
  resume tracking them; guardrails apply immediately.

## Testing

- Unit tests for risk guardrails, dedup, payload validation, and stats math
  with a mocked Tradovate client (TDD).
- Integration dry-run mode (`DRY_RUN=1`) that exercises the full path minus
  real order placement.
