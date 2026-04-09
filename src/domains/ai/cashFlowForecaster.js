'use strict';

/**
 * Cash Flow Forecaster
 * FIN-164: Projects income and expenses for next 30, 60, and 90 days.
 *
 * Uses existing recurrence scores from featureExtractor.js — no LLM cost.
 * Pure function: no side effects, fully testable in isolation.
 *
 * IPC: ai:forecast-cashflow
 * Payload: { transactions: Transaction[], currentBalance?: number, forecastDays?: number[] }
 */

/**
 * @typedef {object} Transaction
 * @property {string}  transaction_id
 * @property {string}  date           ISO date string "YYYY-MM-DD"
 * @property {number}  amount         Negative = debit/expense, positive = credit/income
 * @property {string}  [merchant_name]
 * @property {boolean} [isRecurring]
 * @property {number}  [periodDays]
 * @property {string}  [account_id]
 */

/**
 * @typedef {object} DayBucket
 * @property {string} date             ISO date "YYYY-MM-DD"
 * @property {number} projectedIncome
 * @property {number} projectedExpenses
 * @property {number} projectedBalance
 */

/**
 * @typedef {object} ForecastResult
 * @property {number}     currentBalance
 * @property {DayBucket[]} dailyBuckets
 * @property {{ days: number, balance: number, income: number, expenses: number }[]} summaries
 * @property {string[]}   warnings
 */

const RECURRENCE_MIN_CONFIDENCE = 0.6;

/**
 * Format a Date as "YYYY-MM-DD".
 * @param {Date} d
 * @returns {string}
 */
function toISO(d) {
  return d.toISOString().slice(0, 10);
}

/**
 * Extract recurring transactions — those flagged by featureExtractor,
 * or detected from raw transaction history by frequency analysis.
 *
 * @param {Transaction[]} transactions
 * @returns {Transaction[]}
 */
function extractRecurring(transactions) {
  // If feature-extracted flags exist, use them directly
  const flagged = transactions.filter(
    t => t.isRecurring === true || (t.confidence != null && t.confidence >= RECURRENCE_MIN_CONFIDENCE),
  );
  if (flagged.length > 0) return flagged;

  // Fallback: detect recurring from raw data. Group by normalized merchant + amount bucket,
  // then flag transactions that repeat ≥2 times with a consistent interval (± 5 days).
  const groups = new Map();
  for (const t of transactions) {
    const merchant = (t.merchant_name || t.desc || 'unknown').toLowerCase().trim();
    const amtBucket = Math.round(Math.abs(Number(t.amount)) / 5) * 5; // round to nearest $5
    const key = `${merchant}::${amtBucket}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(t);
  }

  const recurring = [];
  for (const [, group] of groups) {
    if (group.length < 2) continue;
    const sorted = [...group].sort((a, b) => new Date(a.date) - new Date(b.date));
    const gaps = [];
    for (let i = 1; i < sorted.length; i++) {
      gaps.push((new Date(sorted[i].date) - new Date(sorted[i - 1].date)) / 86400000);
    }
    const avgGap = gaps.reduce((s, g) => s + g, 0) / gaps.length;
    const consistent = gaps.every(g => Math.abs(g - avgGap) <= 5);
    if (consistent && avgGap >= 7 && avgGap <= 95) {
      for (const t of sorted) {
        recurring.push({ ...t, periodDays: Math.round(avgGap) });
      }
    }
  }
  return recurring;
}

/**
 * Group transactions by normalized merchant + account.
 * @param {Transaction[]} transactions
 * @returns {Map<string, Transaction[]>}
 */
function groupByMerchantAccount(transactions) {
  const map = new Map();
  for (const t of transactions) {
    const key = `${(t.merchant_name || 'unknown').toLowerCase().trim()}::${t.account_id || ''}`;
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(t);
  }
  return map;
}

/**
 * Given a recurring transaction series, estimate the next N occurrences within
 * the forecast window.
 *
 * @param {Transaction[]} series  Transactions sorted descending by date
 * @param {number}        period  Period in days
 * @param {Date}          from    Forecast start (today)
 * @param {number}        days    Number of days to project
 * @returns {{ date: string, amount: number }[]}
 */
function projectOccurrences(series, period, from, days) {
  if (!series.length || !period || period <= 0) return [];

  const sorted = [...series].sort((a, b) => new Date(b.date) - new Date(a.date));
  const lastDate = new Date(sorted[0].date);
  const avgAmount = series.reduce((s, t) => s + Number(t.amount), 0) / series.length;
  const horizon = new Date(from.getTime() + days * 86400000);
  const results = [];

  let next = new Date(lastDate.getTime() + period * 86400000);
  // Clamp to at most 200 iterations to avoid infinite loops
  let iter = 0;
  while (next <= horizon && iter < 200) {
    if (next >= from) {
      results.push({ date: toISO(next), amount: avgAmount });
    }
    next = new Date(next.getTime() + period * 86400000);
    iter++;
  }
  return results;
}

/**
 * Forecast cash flow for the next 30, 60, and 90 days (or custom buckets).
 *
 * @param {Transaction[]} transactions   Historical transactions (should include feature fields)
 * @param {object}        [opts]
 * @param {number}        [opts.currentBalance]  Starting balance (default 0)
 * @param {number[]}      [opts.forecastDays]    Day horizons (default [30, 60, 90])
 * @returns {ForecastResult}
 */
function forecastCashFlow(transactions, opts = {}) {
  if (!Array.isArray(transactions)) throw new TypeError('transactions must be an array');

  const { currentBalance = 0, forecastDays = [30, 60, 90] } = opts;
  const maxDays = Math.max(...forecastDays, 0);
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  // Build projected events: date → { income, expenses }
  const events = new Map(); // "YYYY-MM-DD" → { income: number, expenses: number }

  const ensureDay = date => {
    if (!events.has(date)) events.set(date, { income: 0, expenses: 0 });
    return events.get(date);
  };

  const recurring = extractRecurring(transactions);
  const grouped = groupByMerchantAccount(recurring);

  for (const [, series] of grouped) {
    const period = series.find(t => t.periodDays)?.periodDays ?? null;
    if (!period) continue;

    const occurrences = projectOccurrences(series, period, today, maxDays);
    for (const { date, amount } of occurrences) {
      const bucket = ensureDay(date);
      if (amount >= 0) {
        bucket.income += amount;
      } else {
        bucket.expenses += Math.abs(amount);
      }
    }
  }

  // Build sorted daily buckets
  const allDates = [];
  for (let i = 0; i < maxDays; i++) {
    const d = new Date(today.getTime() + i * 86400000);
    allDates.push(toISO(d));
  }

  let runningBalance = currentBalance;
  const dailyBuckets = allDates.map(date => {
    const ev = events.get(date) || { income: 0, expenses: 0 };
    runningBalance += ev.income - ev.expenses;
    return {
      date,
      projectedIncome: parseFloat(ev.income.toFixed(2)),
      projectedExpenses: parseFloat(ev.expenses.toFixed(2)),
      projectedBalance: parseFloat(runningBalance.toFixed(2)),
    };
  });

  // Compute summaries per horizon
  const summaries = forecastDays.map(days => {
    const slice = dailyBuckets.slice(0, days);
    return {
      days,
      balance: slice.length ? slice[slice.length - 1].projectedBalance : currentBalance,
      income: parseFloat(slice.reduce((s, d) => s + d.projectedIncome, 0).toFixed(2)),
      expenses: parseFloat(slice.reduce((s, d) => s + d.projectedExpenses, 0).toFixed(2)),
    };
  });

  // Warnings
  const warnings = [];
  for (const bucket of dailyBuckets) {
    if (bucket.projectedBalance < 0) {
      warnings.push(`Projected negative balance on ${bucket.date}: $${bucket.projectedBalance.toFixed(2)}`);
      break; // One warning is enough
    }
  }

  return {
    currentBalance: parseFloat(Number(currentBalance).toFixed(2)),
    dailyBuckets,
    summaries,
    warnings,
  };
}

module.exports = { forecastCashFlow };
