'use strict';

/**
 * Mileage Suggestor (Business Mode)
 * FIN-164: Scans transactions for known business-merchant keywords and
 * generates suggested mileage log entries.
 *
 * Pure function: no side effects, fully testable in isolation.
 *
 * IPC: ai:suggest-mileage
 * Payload: { transactions: Transaction[], businessKeywords?: string[], irs_rate?: number }
 */

/**
 * @typedef {object} MileageSuggestion
 * @property {string} transactionId
 * @property {string} date
 * @property {string} merchantName
 * @property {string} reason         Why this triggered a mileage suggestion
 * @property {number} [suggestedMiles]  Placeholder — user must confirm actual miles
 * @property {number} [deductibleValue] suggestedMiles * irs_rate
 */

/**
 * Default list of business merchant keyword patterns.
 * Callers may override or extend via the `businessKeywords` parameter.
 * @type {string[]}
 */
const DEFAULT_BUSINESS_KEYWORDS = [
  // Office / supplies
  'staples', 'office depot', 'office max', 'amazon business', 'uline',
  // Clients / meetings
  'client', 'conference', 'summit', 'expo', 'meetup', 'convention',
  // Professional services
  'fedex', 'ups', 'usps', 'print', 'notary', 'courthouse',
  // Hardware / tools
  'home depot', 'lowes', 'harbor freight', 'best buy', 'micro center',
  // Fuel (business trips)
  'shell', 'exxon', 'chevron', 'bp', 'speedway', 'pilot', 'love\'s', 'kwik trip',
  // Lodging (business travel)
  'marriott', 'hilton', 'hyatt', 'doubletree', 'holiday inn', 'hampton inn',
  // Vehicle service
  'jiffy lube', 'valvoline', 'firestone', 'midas', 'pep boys', 'autozone',
];

/** IRS standard mileage rate for 2024 business use (cents per mile → dollars). */
const DEFAULT_IRS_RATE = 0.67; // $0.67 per mile (2024 rate)

/** Placeholder suggested miles per trip when actual distance is unknown. */
const PLACEHOLDER_MILES = 0; // User must fill in actual miles

/**
 * Check if a transaction's merchant name matches any business keyword.
 *
 * @param {string}   merchantName
 * @param {string[]} keywords
 * @returns {{ matched: boolean, keyword: string|null }}
 */
function matchBusinessKeyword(merchantName, keywords) {
  const name = (merchantName || '').toLowerCase();
  for (const kw of keywords) {
    if (name.includes(kw.toLowerCase())) {
      return { matched: true, keyword: kw };
    }
  }
  return { matched: false, keyword: null };
}

/**
 * Generate mileage log suggestions from a transaction list.
 *
 * @param {object[]} transactions
 * @param {object}   [opts]
 * @param {string[]} [opts.businessKeywords]  Override/extend default keyword list
 * @param {number}   [opts.irsRate]           IRS rate per mile (default 0.67)
 * @returns {{ suggestions: MileageSuggestion[], totalSuggestedMiles: number, totalDeductibleValue: number }}
 */
function suggestMileage(transactions, opts = {}) {
  if (!Array.isArray(transactions)) throw new TypeError('transactions must be an array');

  const {
    businessKeywords = DEFAULT_BUSINESS_KEYWORDS,
    irsRate = DEFAULT_IRS_RATE,
  } = opts;

  const keywords = [...new Set([...DEFAULT_BUSINESS_KEYWORDS, ...businessKeywords])];
  const suggestions = [];

  for (const txn of transactions) {
    const merchant = txn.merchant_name || txn.name || '';
    const { matched, keyword } = matchBusinessKeyword(merchant, keywords);

    if (!matched) continue;

    const miles = PLACEHOLDER_MILES; // Placeholder — user must enter actual miles
    suggestions.push({
      transactionId: txn.transaction_id || txn.id || '',
      date: txn.date || '',
      merchantName: merchant,
      reason: `Matched business keyword: "${keyword}"`,
      suggestedMiles: miles,
      deductibleValue: parseFloat((miles * irsRate).toFixed(2)),
    });
  }

  const totalSuggestedMiles = suggestions.reduce((s, sg) => s + sg.suggestedMiles, 0);
  const totalDeductibleValue = parseFloat(
    (totalSuggestedMiles * irsRate).toFixed(2),
  );

  return { suggestions, totalSuggestedMiles, totalDeductibleValue };
}

module.exports = { suggestMileage, DEFAULT_BUSINESS_KEYWORDS, DEFAULT_IRS_RATE };
