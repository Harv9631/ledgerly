'use strict';

/**
 * Subscription Detector
 * FIN-164: Scans transactions for high-confidence recurring charges and detects duplicates.
 *
 * Wraps existing featureExtractor.js recurrence detection output.
 * Pure function: no side effects, fully testable in isolation.
 *
 * IPC: ai:detect-subscriptions
 * Payload: { transactions: Transaction[] }
 */

/**
 * @typedef {object} Subscription
 * @property {string}   merchantName
 * @property {string}   accountId
 * @property {number}   monthlyCost
 * @property {number}   annualCost
 * @property {number}   periodDays
 * @property {number}   confidence
 * @property {string}   lastDate
 * @property {boolean}  isDuplicate    Same merchant detected on multiple accounts
 * @property {string[]} duplicateAccounts  Other account IDs with same merchant
 */

/**
 * @typedef {object} DetectionResult
 * @property {Subscription[]} subscriptions
 * @property {Subscription[]} duplicates
 * @property {number}         totalMonthlyCost
 * @property {number}         totalAnnualCost
 */

const DEFAULT_MIN_CONFIDENCE = 0.5;
const DEFAULT_MIN_OCCURRENCES = 2;

/**
 * Normalize a merchant name for grouping comparison.
 * @param {string} name
 * @returns {string}
 */
function normalizeMerchant(name) {
  return (name || 'unknown')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '')
    .slice(0, 40);
}

/**
 * Estimate monthly cost from average amount and period in days.
 * @param {number} avgAmount  Absolute value
 * @param {number} periodDays
 * @returns {number}
 */
function toMonthlyCost(avgAmount, periodDays) {
  if (!periodDays || periodDays <= 0) return 0;
  return parseFloat(((avgAmount / periodDays) * 30.44).toFixed(2));
}

/**
 * Detect subscriptions from a transaction list.
 *
 * Expects transactions to have featureExtractor fields:
 *   isRecurring {boolean}, periodDays {number|null}, confidence {number|null}
 *
 * @param {object[]} transactions
 * @param {object}   [opts]
 * @param {number}   [opts.minConfidence]    Minimum recurrence confidence (default 0.5)
 * @param {number}   [opts.minOccurrences]   Minimum occurrences to qualify (default 2)
 * @returns {DetectionResult}
 */
function detectSubscriptions(transactions, opts = {}) {
  if (!Array.isArray(transactions)) throw new TypeError('transactions must be an array');

  const { minConfidence = DEFAULT_MIN_CONFIDENCE, minOccurrences = DEFAULT_MIN_OCCURRENCES } = opts;

  // Group by normalized merchant + account
  const groups = new Map(); // key → { merchant, account, txns }

  for (const t of transactions) {
    const merchant = normalizeMerchant(t.merchant_name);
    const account = t.account_id || '';
    const key = `${merchant}::${account}`;

    if (!groups.has(key)) {
      groups.set(key, {
        merchantName: (t.merchant_name || 'Unknown').trim(),
        accountId: account,
        txns: [],
      });
    }
    groups.get(key).txns.push(t);
  }

  const subscriptions = [];

  for (const [, group] of groups) {
    const recurring = group.txns.filter(
      t => t.isRecurring === true || (t.confidence != null && t.confidence >= minConfidence),
    );

    if (recurring.length < minOccurrences) continue;

    const periodDays =
      recurring.find(t => t.periodDays)?.periodDays ??
      // Estimate from transaction dates if no explicit period
      (() => {
        if (recurring.length < 2) return null;
        const dates = recurring.map(t => new Date(t.date).getTime()).sort((a, b) => a - b);
        const gaps = [];
        for (let i = 1; i < dates.length; i++) gaps.push((dates[i] - dates[i - 1]) / 86400000);
        return parseFloat((gaps.reduce((s, g) => s + g, 0) / gaps.length).toFixed(1));
      })();

    if (!periodDays) continue;

    const avgConfidence =
      recurring.reduce((s, t) => s + (t.confidence ?? 0.7), 0) / recurring.length;
    const avgAmount =
      recurring.reduce((s, t) => s + Math.abs(Number(t.amount)), 0) / recurring.length;
    const sortedDates = recurring.map(t => t.date).sort();
    const lastDate = sortedDates[sortedDates.length - 1];

    const monthlyCost = toMonthlyCost(avgAmount, periodDays);

    subscriptions.push({
      merchantName: group.merchantName,
      accountId: group.accountId,
      monthlyCost,
      annualCost: parseFloat((monthlyCost * 12).toFixed(2)),
      periodDays,
      confidence: parseFloat(avgConfidence.toFixed(4)),
      lastDate,
      isDuplicate: false,
      duplicateAccounts: [],
    });
  }

  // Flag duplicates: same normalized merchant across multiple accounts
  const byMerchant = new Map();
  for (const sub of subscriptions) {
    const key = normalizeMerchant(sub.merchantName);
    if (!byMerchant.has(key)) byMerchant.set(key, []);
    byMerchant.get(key).push(sub);
  }

  for (const [, subs] of byMerchant) {
    if (subs.length > 1) {
      const accounts = subs.map(s => s.accountId);
      for (const sub of subs) {
        sub.isDuplicate = true;
        sub.duplicateAccounts = accounts.filter(a => a !== sub.accountId);
      }
    }
  }

  const duplicates = subscriptions.filter(s => s.isDuplicate);
  const totalMonthlyCost = parseFloat(
    subscriptions.reduce((s, sub) => s + sub.monthlyCost, 0).toFixed(2),
  );

  return {
    subscriptions,
    duplicates,
    totalMonthlyCost,
    totalAnnualCost: parseFloat((totalMonthlyCost * 12).toFixed(2)),
  };
}

module.exports = { detectSubscriptions };
