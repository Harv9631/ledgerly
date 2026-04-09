'use strict';

/**
 * Trend Detection Service
 * FIN-137: Detects rising debt, seasonal income dips, and recurring budget overages.
 *
 * Algorithm:
 *   - Group transactions by category and month
 *   - Compare current month total vs. 3-month rolling average
 *   - Emit a trend record when |deviation| > threshold (default 20%)
 *
 * Conventions:
 *   - Positive amount = debit/expense  (matches Plaid convention)
 *   - Negative amount = credit/income
 *   - "income" category group: any category whose l0 is 'Transfer' or 'Income',
 *     or whose personal_finance_category starts with 'INCOME' or 'TRANSFER_IN'
 */

const DEVIATION_THRESHOLD_DEFAULT = 0.20; // 20%

/**
 * Return an ISO "YYYY-MM" month key for a date string.
 * @param {string} dateStr  e.g. "2024-03-15"
 * @returns {string}
 */
function monthKey(dateStr) {
  return dateStr.slice(0, 7);
}

/**
 * Return the N month keys immediately before `currentMonthKey` (exclusive).
 * @param {string} currentMonthKey  "YYYY-MM"
 * @param {number} n
 * @returns {string[]}
 */
function priorMonths(currentMonthKey, n) {
  const [y, m] = currentMonthKey.split('-').map(Number);
  const result = [];
  for (let i = 1; i <= n; i++) {
    let pm = m - i;
    let py = y;
    while (pm <= 0) { pm += 12; py -= 1; }
    result.push(`${py}-${String(pm).padStart(2, '0')}`);
  }
  return result;
}

/**
 * Derive a stable category key from a transaction.
 * Uses personal_finance_category if present, else plaid_category[0], else 'Uncategorized'.
 * @param {object} txn
 * @returns {string}
 */
function categoryKey(txn) {
  if (txn.personal_finance_category) return txn.personal_finance_category;
  if (Array.isArray(txn.plaid_category) && txn.plaid_category[0]) return txn.plaid_category[0];
  return 'Uncategorized';
}

/**
 * Determine if a transaction represents income (credit) based on category hints.
 * @param {object} txn
 * @returns {boolean}
 */
function isIncomeTxn(txn) {
  const pfc = (txn.personal_finance_category || '').toUpperCase();
  if (pfc.startsWith('INCOME') || pfc.startsWith('TRANSFER_IN')) return true;
  if (Array.isArray(txn.plaid_category)) {
    const l0 = (txn.plaid_category[0] || '').toLowerCase();
    if (l0 === 'transfer' || l0 === 'income') return true;
  }
  // Negative amount without a debt/transfer category = income
  return txn.amount < 0;
}

/**
 * Group transactions into a nested map: category → month → total amount (absolute).
 *
 * @param {object[]} transactions  Array of transaction objects
 * @returns {Map<string, Map<string, number>>}
 */
function buildCategoryMonthMap(transactions) {
  const map = new Map();
  for (const txn of transactions) {
    const cat = categoryKey(txn);
    const mk = monthKey(txn.date);
    if (!map.has(cat)) map.set(cat, new Map());
    const monthMap = map.get(cat);
    monthMap.set(mk, (monthMap.get(mk) ?? 0) + Math.abs(Number(txn.amount)));
  }
  return map;
}

/**
 * Compute the rolling average for a set of prior months.
 * Returns null if no data is available.
 *
 * @param {Map<string, number>} monthMap
 * @param {string[]} priorKeys
 * @returns {number|null}
 */
function rollingAverage(monthMap, priorKeys) {
  let total = 0;
  let count = 0;
  for (const mk of priorKeys) {
    if (monthMap.has(mk)) {
      total += monthMap.get(mk);
      count++;
    }
  }
  return count > 0 ? total / count : null;
}

/**
 * Detect spending / income trends for the given current month.
 *
 * @param {object[]} transactions       All transactions (current + historical)
 * @param {object}   [opts]
 * @param {string}   [opts.currentMonth]          "YYYY-MM"; defaults to most recent month in data
 * @param {number}   [opts.deviationThreshold]    Fraction (0–1); default 0.20
 * @param {number}   [opts.rollingMonths]         How many prior months to average; default 3
 * @returns {TrendRecord[]}
 *
 * @typedef {object} TrendRecord
 * @property {string} category
 * @property {string} month
 * @property {number} currentTotal
 * @property {number} rollingAvg
 * @property {number} deviationPct     Signed: positive = above avg, negative = below avg
 * @property {'rising'|'falling'}  direction
 * @property {'spending'|'income'} kind
 */
function detectTrends(transactions, opts = {}) {
  if (!Array.isArray(transactions)) throw new TypeError('transactions must be an array');

  const {
    deviationThreshold = DEVIATION_THRESHOLD_DEFAULT,
    rollingMonths = 3,
  } = opts;

  if (transactions.length === 0) return [];

  // Determine current month: either provided or derived from most recent txn date
  let currentMonth = opts.currentMonth;
  if (!currentMonth) {
    const dates = transactions.map(t => t.date).filter(Boolean).sort();
    currentMonth = monthKey(dates[dates.length - 1]);
  }

  const priorKeys = priorMonths(currentMonth, rollingMonths);

  // Separate spending and income
  const spending = transactions.filter(t => !isIncomeTxn(t));
  const income   = transactions.filter(t => isIncomeTxn(t));

  const results = [];

  for (const [kind, group] of [['spending', spending], ['income', income]]) {
    const catMonthMap = buildCategoryMonthMap(group);

    for (const [cat, monthMap] of catMonthMap) {
      const currentTotal = monthMap.get(currentMonth);
      if (currentTotal === undefined) continue; // no data this month

      const avg = rollingAverage(monthMap, priorKeys);
      if (avg === null || avg === 0) continue; // no historical baseline

      const deviationPct = (currentTotal - avg) / avg;

      if (Math.abs(deviationPct) < deviationThreshold) continue;

      results.push({
        category:     cat,
        month:        currentMonth,
        currentTotal: parseFloat(currentTotal.toFixed(2)),
        rollingAvg:   parseFloat(avg.toFixed(2)),
        deviationPct: parseFloat(deviationPct.toFixed(4)),
        direction:    deviationPct > 0 ? 'rising' : 'falling',
        kind,
      });
    }
  }

  return results;
}

module.exports = {
  detectTrends,
  // Exported for testing
  monthKey,
  priorMonths,
  categoryKey,
  rollingAverage,
  buildCategoryMonthMap,
  DEVIATION_THRESHOLD_DEFAULT,
};
