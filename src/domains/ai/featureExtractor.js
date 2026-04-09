'use strict';

/**
 * Feature Extractor
 * Converts a normalized transaction + account context into the ML feature
 * row that maps directly to the `transaction_features` DB schema (FIN-133).
 *
 * Pipeline step 2 of 3: normalization → feature extraction → storage
 */

const {
  normalizeTransaction,
  encodeAccountType,
} = require('./normalization');

const FEATURE_VERSION = 1;

/**
 * Compute a z-score for an amount given a rolling mean and std-dev.
 * Returns null when standard deviation is 0 or missing.
 * @param {number} amountAbs
 * @param {number} mean
 * @param {number} stdDev
 * @returns {number|null}
 */
function computeZScore(amountAbs, mean, stdDev) {
  if (!Number.isFinite(mean) || !Number.isFinite(stdDev) || stdDev <= 0) return null;
  return parseFloat(((amountAbs - mean) / stdDev).toFixed(6));
}

/**
 * Classify whether a transaction appears to be recurring given a list of
 * same-merchant transactions sorted by date (ascending).
 *
 * Uses a simple period-detection heuristic: if the median inter-arrival gap
 * is ≤ 35 days, treat it as recurring and estimate the period.
 *
 * @param {Array<{date: string}>} sameAccountMerchantHistory  prior txns, same normalized merchant
 * @returns {{ isRecurring: boolean, periodDays: number|null, confidence: number|null }}
 */
function detectRecurrence(sameAccountMerchantHistory) {
  if (!Array.isArray(sameAccountMerchantHistory) || sameAccountMerchantHistory.length < 2) {
    return { isRecurring: false, periodDays: null, confidence: null };
  }

  const dates = sameAccountMerchantHistory
    .map(t => new Date(t.date).getTime())
    .filter(n => Number.isFinite(n))
    .sort((a, b) => a - b);

  if (dates.length < 2) return { isRecurring: false, periodDays: null, confidence: null };

  const gaps = [];
  for (let i = 1; i < dates.length; i++) {
    gaps.push((dates[i] - dates[i - 1]) / 86_400_000); // ms → days
  }

  gaps.sort((a, b) => a - b);
  const median = gaps[Math.floor(gaps.length / 2)];

  if (median > 35) return { isRecurring: false, periodDays: null, confidence: null };

  // Confidence: fraction of gaps within 5 days of median
  const close = gaps.filter(g => Math.abs(g - median) <= 5).length;
  const confidence = parseFloat((close / gaps.length).toFixed(4));

  return {
    isRecurring: true,
    periodDays:  Math.round(median),
    confidence,
  };
}

/**
 * Extract ML-ready features from a single transaction.
 *
 * @param {object} txn            Raw Plaid transaction object
 * @param {object} [ctx={}]       Account context
 * @param {number} [ctx.accountMean90d]      90-day rolling mean for the account
 * @param {number} [ctx.accountStdDev90d]    90-day rolling std-dev for the account
 * @param {number} [ctx.runningBalanceBefore] Account balance before this transaction
 * @param {string} [ctx.accountType]         Account type (depository|credit|loan|investment)
 * @param {Array}  [ctx.merchantHistory]     Prior txns for this merchant on this account
 * @returns {object}  Feature row matching transaction_features schema
 */
function extractFeatures(txn, ctx = {}) {
  if (!txn || typeof txn !== 'object') throw new TypeError('txn must be an object');
  if (!txn.transaction_id) throw new TypeError('txn.transaction_id is required');

  const norm = normalizeTransaction(txn);
  const df = norm.dateFeatures;

  const amountAbs = norm.amount_abs;
  const amountLog = parseFloat(norm.amount_log.toFixed(6));
  const amountZScore = computeZScore(
    amountAbs,
    ctx.accountMean90d,
    ctx.accountStdDev90d
  );

  const recurrence = detectRecurrence(ctx.merchantHistory);

  return {
    transaction_id:           norm.transaction_id,
    feature_version:          FEATURE_VERSION,

    // Numeric / amount
    amount_abs:               parseFloat(amountAbs.toFixed(2)),
    amount_log:               amountLog,
    amount_z_score:           amountZScore,

    // Temporal
    day_of_week:              df ? df.dayOfWeek    : null,
    day_of_month:             df ? df.dayOfMonth   : null,
    month_of_year:            df ? df.monthOfYear  : null,
    quarter:                  df ? df.quarter      : null,
    is_weekend:               df ? df.isWeekend    : null,
    is_month_start:           df ? df.isMonthStart : null,
    is_month_end:             df ? df.isMonthEnd   : null,

    // Merchant
    merchant_name_normalized: norm.merchant_name_normalized,
    payment_channel_enc:      norm.payment_channel_enc,
    has_merchant_id:          norm.has_merchant_id,

    // Recurrence
    is_recurring:             recurrence.isRecurring,
    recurrence_period_days:   recurrence.periodDays,
    recurrence_confidence:    recurrence.confidence,

    // Account context
    account_type_enc:         encodeAccountType(ctx.accountType),
    running_balance_before:   ctx.runningBalanceBefore ?? null,

    // Plaid category hints
    plaid_category_l0:        norm.plaid_category_l0,
    plaid_category_l1:        norm.plaid_category_l1,
  };
}

module.exports = {
  extractFeatures,
  detectRecurrence,
  computeZScore,
  FEATURE_VERSION,
};
