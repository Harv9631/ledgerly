'use strict';

/**
 * Anomaly Alerts Service
 * FIN-137: Flags unusual financial activity and pushes alerts to the notification queue.
 *
 * Rules:
 *   1. Unusual charge   – amount > 2× this merchant's prior average (same account)
 *   2. Income drop      – current month income > 30% below 3-month prior average
 *   3. Debt acceleration – new debt (positive amount on credit/loan) > $500 in 7 days
 *
 * Designed to be triggered on each transaction write (rules 1 & 3) or on a
 * daily/monthly schedule (rule 2).  All detection functions are pure and
 * storage-agnostic so callers can provide any data source.
 */

/** @typedef {'unusual_charge'|'income_drop'|'debt_acceleration'} AlertType */

/**
 * Create a structured alert object.
 *
 * @param {AlertType} type
 * @param {object}    payload  Rule-specific context
 * @returns {Alert}
 *
 * @typedef {object} Alert
 * @property {AlertType} type
 * @property {number}    severity  0.0–1.0
 * @property {object}    details
 * @property {Date}      detectedAt
 */
function makeAlert(type, severity, details) {
  return { type, severity: parseFloat(severity.toFixed(4)), details, detectedAt: new Date() };
}

// ── Rule 1: Unusual Charge ────────────────────────────────────────────────────

/**
 * Flag a transaction if its absolute amount exceeds 2× the merchant's historical average
 * for the same account.
 *
 * @param {object}   txn                        The new transaction
 * @param {object[]} merchantHistory             Prior transactions for this merchant on this account
 * @param {object}   [opts]
 * @param {number}   [opts.multiplierThreshold]  Default 2.0
 * @returns {Alert|null}
 */
function detectUnusualCharge(txn, merchantHistory, opts = {}) {
  if (!txn || !txn.transaction_id) throw new TypeError('txn.transaction_id is required');
  if (!Array.isArray(merchantHistory)) throw new TypeError('merchantHistory must be an array');

  const { multiplierThreshold = 2.0 } = opts;

  if (merchantHistory.length === 0) return null;

  const amounts = merchantHistory.map(t => Math.abs(Number(t.amount)));
  const avg = amounts.reduce((s, a) => s + a, 0) / amounts.length;

  if (avg <= 0) return null;

  const currentAbs = Math.abs(Number(txn.amount));
  const ratio = currentAbs / avg;

  if (ratio < multiplierThreshold) return null;

  // Severity scales from 0 (exactly at threshold) toward 1 (very large spike)
  const severity = Math.min(1, (ratio - multiplierThreshold) / multiplierThreshold);

  return makeAlert('unusual_charge', severity, {
    transaction_id:   txn.transaction_id,
    merchant_name:    txn.merchant_name ?? txn.name,
    amount:           parseFloat(currentAbs.toFixed(2)),
    merchantAvg:      parseFloat(avg.toFixed(2)),
    ratio:            parseFloat(ratio.toFixed(4)),
    threshold:        multiplierThreshold,
  });
}

// ── Rule 2: Income Drop ───────────────────────────────────────────────────────

/**
 * Return an ISO "YYYY-MM" month key.
 * @param {string} dateStr
 * @returns {string}
 */
function _monthKey(dateStr) {
  return dateStr.slice(0, 7);
}

/**
 * Detect a sudden income drop: current month < (1 – threshold) × 3-month rolling avg.
 *
 * @param {object[]} incomeTransactions   All income transactions (current + historical)
 * @param {object}   [opts]
 * @param {string}   [opts.currentMonth]  "YYYY-MM"; defaults to most recent in data
 * @param {number}   [opts.dropThreshold] Fraction below avg to trigger (default 0.30)
 * @param {number}   [opts.rollingMonths] Default 3
 * @returns {Alert|null}
 */
function detectIncomeDrop(incomeTransactions, opts = {}) {
  if (!Array.isArray(incomeTransactions)) throw new TypeError('incomeTransactions must be an array');

  const { dropThreshold = 0.30, rollingMonths = 3 } = opts;

  if (incomeTransactions.length === 0) return null;

  let currentMonth = opts.currentMonth;
  if (!currentMonth) {
    const dates = incomeTransactions.map(t => t.date).filter(Boolean).sort();
    currentMonth = _monthKey(dates[dates.length - 1]);
  }

  // Build month → total income map (use absolute value)
  const monthTotals = new Map();
  for (const txn of incomeTransactions) {
    const mk = _monthKey(txn.date);
    monthTotals.set(mk, (monthTotals.get(mk) ?? 0) + Math.abs(Number(txn.amount)));
  }

  const currentIncome = monthTotals.get(currentMonth) ?? 0;

  // Collect prior months
  const [y, m] = currentMonth.split('-').map(Number);
  let totalPrior = 0;
  let priorCount = 0;
  for (let i = 1; i <= rollingMonths; i++) {
    let pm = m - i;
    let py = y;
    while (pm <= 0) { pm += 12; py -= 1; }
    const mk = `${py}-${String(pm).padStart(2, '0')}`;
    if (monthTotals.has(mk)) {
      totalPrior += monthTotals.get(mk);
      priorCount++;
    }
  }

  if (priorCount === 0) return null;

  const priorAvg = totalPrior / priorCount;
  if (priorAvg === 0) return null;

  const dropPct = (priorAvg - currentIncome) / priorAvg;

  if (dropPct < dropThreshold) return null;

  const severity = Math.min(1, dropPct);

  return makeAlert('income_drop', severity, {
    month:        currentMonth,
    currentIncome: parseFloat(currentIncome.toFixed(2)),
    priorAvg:     parseFloat(priorAvg.toFixed(2)),
    dropPct:      parseFloat(dropPct.toFixed(4)),
    threshold:    dropThreshold,
  });
}

// ── Rule 3: Debt Acceleration ─────────────────────────────────────────────────

/**
 * Detect debt acceleration: new debt (positive-amount credit/loan transactions) > $500
 * within a rolling 7-day window ending at the current transaction's date.
 *
 * @param {object}   txn              The new (most recent) transaction
 * @param {object[]} recentDebtTxns   All credit/loan transactions in the last 7 days
 *                                    INCLUDING txn itself.
 * @param {object}   [opts]
 * @param {number}   [opts.windowDays]   Default 7
 * @param {number}   [opts.amountLimit]  Default 500
 * @returns {Alert|null}
 */
function detectDebtAcceleration(txn, recentDebtTxns, opts = {}) {
  if (!txn || !txn.transaction_id) throw new TypeError('txn.transaction_id is required');
  if (!Array.isArray(recentDebtTxns)) throw new TypeError('recentDebtTxns must be an array');

  const { windowDays = 7, amountLimit = 500 } = opts;

  if (recentDebtTxns.length === 0) return null;

  const cutoff = new Date(txn.date);
  cutoff.setDate(cutoff.getDate() - windowDays);

  const windowTxns = recentDebtTxns.filter(t => new Date(t.date) >= cutoff);
  const totalDebt = windowTxns.reduce((s, t) => s + Math.abs(Number(t.amount)), 0);

  if (totalDebt <= amountLimit) return null;

  const severity = Math.min(1, (totalDebt - amountLimit) / amountLimit);

  return makeAlert('debt_acceleration', severity, {
    transaction_id: txn.transaction_id,
    windowDays,
    totalNewDebt:   parseFloat(totalDebt.toFixed(2)),
    limit:          amountLimit,
    txnCount:       windowTxns.length,
  });
}

// ── Notification Queue Push ───────────────────────────────────────────────────

/**
 * Push one or more alerts onto the user notification queue.
 * The queue is a simple in-memory FIFO; swap for a persistent store in production.
 *
 * @param {Alert|Alert[]} alerts
 * @param {object}        queue    Must implement push(item) and optionally emit('alert', item)
 */
function pushAlerts(alerts, queue) {
  if (!queue || typeof queue.push !== 'function') {
    throw new TypeError('queue must implement push(item)');
  }
  const list = Array.isArray(alerts) ? alerts : [alerts];
  for (const alert of list) {
    if (alert) queue.push(alert);
  }
}

/**
 * Convenience: run all three detection rules against a single transaction event.
 *
 * @param {object} txn
 * @param {object} ctx
 * @param {object[]} ctx.merchantHistory    Prior txns for this merchant (same account)
 * @param {object[]} ctx.incomeTransactions All income txns (current + 3 prior months)
 * @param {object[]} ctx.recentDebtTxns     Credit/loan txns in last 7 days
 * @param {object}   [ctx.opts]             Per-rule option overrides
 * @returns {Alert[]}
 */
function analyzeTransaction(txn, ctx = {}) {
  const alerts = [];

  const chargeAlert = detectUnusualCharge(
    txn,
    ctx.merchantHistory ?? [],
    ctx.opts?.unusualCharge
  );
  if (chargeAlert) alerts.push(chargeAlert);

  if (ctx.incomeTransactions?.length) {
    const incomeAlert = detectIncomeDrop(ctx.incomeTransactions, ctx.opts?.incomeDrop);
    if (incomeAlert) alerts.push(incomeAlert);
  }

  if (ctx.recentDebtTxns?.length) {
    const debtAlert = detectDebtAcceleration(
      txn,
      ctx.recentDebtTxns,
      ctx.opts?.debtAcceleration
    );
    if (debtAlert) alerts.push(debtAlert);
  }

  return alerts;
}

module.exports = {
  detectUnusualCharge,
  detectIncomeDrop,
  detectDebtAcceleration,
  analyzeTransaction,
  pushAlerts,
};
