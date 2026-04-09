'use strict';

/**
 * Normalization Service
 * Standardizes merchant names, amounts, dates, and currency codes
 * before ML feature extraction.
 *
 * Pipeline step 1 of 3: normalization → feature extraction → storage
 */

const PAYMENT_CHANNEL_MAP = { online: 0, in_store: 1, other: 2 };
const ACCOUNT_TYPE_MAP = { depository: 0, credit: 1, loan: 2, investment: 3 };

const CURRENCY_ALIASES = {
  '$': 'USD', '€': 'EUR', '£': 'GBP', '¥': 'JPY',
};

// Common noise tokens to strip from merchant names (preserves brand)
const NOISE_RE = /\b(llc|inc|corp|ltd|co|dba|the|a)\b\.?/gi;
// Strip punctuation except spaces and hyphens
const PUNCT_RE = /[^\w\s-]/g;
// Collapse whitespace
const SPACE_RE = /\s{2,}/g;

/**
 * Normalize a merchant / transaction name to a canonical lowercase string.
 * @param {string|null} name
 * @returns {string}
 */
function normalizeMerchantName(name) {
  if (!name) return '';
  return name
    .toLowerCase()
    .replace(NOISE_RE, ' ')
    .replace(PUNCT_RE, ' ')
    .replace(SPACE_RE, ' ')
    .trim();
}

/**
 * Return the absolute value of an amount (Plaid amounts: positive = debit).
 * @param {number} amount
 * @returns {number}
 */
function normalizeAmount(amount) {
  const n = Number(amount);
  if (!Number.isFinite(n)) return 0;
  return Math.abs(n);
}

/**
 * log1p of the absolute amount — reduces skew for ML models.
 * @param {number} amount
 * @returns {number}
 */
function logTransformAmount(amount) {
  return Math.log1p(normalizeAmount(amount));
}

/**
 * Parse a date string or Date to a JS Date. Returns null on failure.
 * @param {string|Date|null} value
 * @returns {Date|null}
 */
function parseDate(value) {
  if (!value) return null;
  const d = value instanceof Date ? value : new Date(value);
  return isNaN(d.getTime()) ? null : d;
}

/**
 * Extract temporal features from a date.
 * @param {string|Date|null} value
 * @returns {{ dayOfWeek:number, dayOfMonth:number, monthOfYear:number,
 *             quarter:number, isWeekend:boolean, isMonthStart:boolean, isMonthEnd:boolean }|null}
 */
function extractDateFeatures(value) {
  const d = parseDate(value);
  if (!d) return null;
  const dom = d.getUTCDate();
  const mon = d.getUTCMonth() + 1; // 1-12
  const dow = d.getUTCDay();       // 0=Sun…6=Sat — convert to 0=Mon…6=Sun
  const dowMon = (dow + 6) % 7;   // 0=Mon…6=Sun
  return {
    dayOfWeek:    dowMon,
    dayOfMonth:   dom,
    monthOfYear:  mon,
    quarter:      Math.ceil(mon / 3),
    isWeekend:    dowMon >= 5,
    isMonthStart: dom <= 5,
    isMonthEnd:   dom >= 25,
  };
}

/**
 * Canonicalize a currency code. Accepts ISO 4217 strings or common symbols.
 * @param {string|null} code
 * @returns {string}
 */
function normalizeCurrency(code) {
  if (!code) return 'USD';
  const trimmed = code.trim();
  return CURRENCY_ALIASES[trimmed] || trimmed.toUpperCase();
}

/**
 * Encode payment_channel to a numeric value.
 * @param {string|null} channel
 * @returns {number}
 */
function encodePaymentChannel(channel) {
  if (!channel) return PAYMENT_CHANNEL_MAP.other;
  return PAYMENT_CHANNEL_MAP[channel.toLowerCase()] ?? PAYMENT_CHANNEL_MAP.other;
}

/**
 * Encode account type to a numeric value.
 * @param {string|null} type
 * @returns {number}
 */
function encodeAccountType(type) {
  if (!type) return 0;
  return ACCOUNT_TYPE_MAP[type.toLowerCase()] ?? 0;
}

/**
 * Normalize a full Plaid transaction object.
 * Returns a normalized representation (does not mutate input).
 * @param {object} txn  Plaid transaction
 * @returns {object}
 */
function normalizeTransaction(txn) {
  if (!txn || typeof txn !== 'object') throw new TypeError('txn must be an object');
  const date = txn.date || txn.authorized_date;
  return {
    transaction_id:         txn.transaction_id,
    account_id:             txn.account_id,
    amount_abs:             normalizeAmount(txn.amount),
    amount_log:             logTransformAmount(txn.amount),
    iso_currency_code:      normalizeCurrency(txn.iso_currency_code),
    merchant_name_normalized: normalizeMerchantName(txn.merchant_name || txn.name),
    payment_channel_enc:    encodePaymentChannel(txn.payment_channel),
    has_merchant_id:        Boolean(txn.merchant_id),
    date,
    dateFeatures:           extractDateFeatures(date),
    plaid_category_l0:      Array.isArray(txn.plaid_category) ? (txn.plaid_category[0] || null) : null,
    plaid_category_l1:      Array.isArray(txn.plaid_category) ? (txn.plaid_category[1] || null) : null,
  };
}

module.exports = {
  normalizeMerchantName,
  normalizeAmount,
  logTransformAmount,
  parseDate,
  extractDateFeatures,
  normalizeCurrency,
  encodePaymentChannel,
  encodeAccountType,
  normalizeTransaction,
  PAYMENT_CHANNEL_MAP,
  ACCOUNT_TYPE_MAP,
};
