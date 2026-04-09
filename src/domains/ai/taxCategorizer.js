'use strict';

/**
 * Tax Categorizer (Business Mode)
 * FIN-164: Maps transaction categories to IRS Schedule C line items and
 * computes estimated deductible amounts.
 *
 * Pure function: no side effects, fully testable in isolation.
 *
 * IPC: ai:categorize-taxes
 * Payload: { transactions: Transaction[], dateRange?: { start: string, end: string } }
 */

/**
 * @typedef {object} TaxLineItem
 * @property {string}   scheduleC         IRS Schedule C line description
 * @property {number}   deductiblePct     Percentage deductible (0–1)
 * @property {string[]} categories        Transaction category keywords that map here
 * @property {string[]} merchantKeywords  Merchant name fragments that map here
 */

/**
 * IRS Schedule C mapping table.
 * Keys are Schedule C line names; values describe matching rules.
 * @type {TaxLineItem[]}
 */
const SCHEDULE_C_RULES = [
  {
    scheduleC: 'Advertising',
    deductiblePct: 1.0,
    categories: ['advertising', 'marketing', 'promotion', 'social media', 'seo', 'pr'],
    merchantKeywords: ['google ads', 'facebook ads', 'mailchimp', 'hubspot', 'hootsuite'],
  },
  {
    scheduleC: 'Car and truck expenses',
    deductiblePct: 1.0,
    categories: ['auto', 'vehicle', 'gas', 'fuel', 'parking', 'toll', 'car repair', 'car insurance'],
    merchantKeywords: ['shell', 'exxon', 'chevron', 'bp', 'speedway', 'uber', 'lyft', 'enterprise rent'],
  },
  {
    scheduleC: 'Meals (50% deductible)',
    deductiblePct: 0.5,
    categories: ['meals', 'dining', 'restaurants', 'food', 'coffee', 'entertainment'],
    merchantKeywords: ['starbucks', 'doordash', 'ubereats', 'grubhub', 'chipotle', 'subway', "mcdonald's"],
  },
  {
    scheduleC: 'Office expense',
    deductiblePct: 1.0,
    categories: ['office supplies', 'stationery', 'postage', 'shipping'],
    merchantKeywords: ['staples', 'office depot', 'amazon', 'fedex', 'ups', 'usps'],
  },
  {
    scheduleC: 'Rent or lease (business property)',
    deductiblePct: 1.0,
    categories: ['rent', 'lease', 'coworking', 'office space'],
    merchantKeywords: ['regus', 'wework', 'industrious', 'spaces', 'cowork'],
  },
  {
    scheduleC: 'Utilities',
    deductiblePct: 1.0,
    categories: ['utilities', 'electricity', 'water', 'internet', 'phone', 'cell phone', 'broadband'],
    merchantKeywords: ['at&t', 'verizon', 'comcast', 'xfinity', 't-mobile', 'spectrum'],
  },
  {
    scheduleC: 'Professional services',
    deductiblePct: 1.0,
    categories: ['legal', 'accounting', 'consulting', 'professional services', 'bookkeeping'],
    merchantKeywords: ['legalzoom', 'intuit', 'quickbooks', 'freshbooks', 'xero'],
  },
  {
    scheduleC: 'Home office (proportional)',
    deductiblePct: 1.0,   // caller adjusts by sqft ratio
    categories: ['home office', 'mortgage', 'home insurance', 'hoa'],
    merchantKeywords: [],
  },
  {
    scheduleC: 'Software and subscriptions',
    deductiblePct: 1.0,
    categories: ['software', 'saas', 'subscription', 'cloud', 'hosting', 'domain'],
    merchantKeywords: ['adobe', 'slack', 'zoom', 'dropbox', 'github', 'aws', 'digitalocean', 'godaddy'],
  },
  {
    scheduleC: 'Travel',
    deductiblePct: 1.0,
    categories: ['travel', 'airfare', 'flight', 'hotel', 'lodging', 'conference', 'train'],
    merchantKeywords: ['delta', 'united', 'southwest', 'marriott', 'hilton', 'airbnb', 'expedia'],
  },
  {
    scheduleC: 'Education and training',
    deductiblePct: 1.0,
    categories: ['education', 'training', 'course', 'books', 'conference fee', 'seminar'],
    merchantKeywords: ['udemy', 'coursera', 'linkedin learning', 'pluralsight', 'skillshare'],
  },
  {
    scheduleC: 'Insurance (business)',
    deductiblePct: 1.0,
    categories: ['business insurance', 'liability insurance', 'health insurance'],
    merchantKeywords: ['hiscox', 'next insurance', 'coverhound'],
  },
];

/**
 * Match a single transaction to a Schedule C line item.
 *
 * @param {object} txn
 * @returns {TaxLineItem|null}
 */
function matchRule(txn) {
  const category = (txn.category || txn.personal_finance_category?.primary || '').toLowerCase();
  const merchant = (txn.merchant_name || txn.name || '').toLowerCase();

  for (const rule of SCHEDULE_C_RULES) {
    const catMatch = rule.categories.some(c => category.includes(c));
    const merchantMatch = rule.merchantKeywords.some(k => merchant.includes(k));
    if (catMatch || merchantMatch) return rule;
  }
  return null;
}

/**
 * @typedef {object} TaxSummaryLine
 * @property {string} scheduleC
 * @property {number} totalAmount
 * @property {number} deductibleAmount
 * @property {number} deductiblePct
 * @property {number} transactionCount
 */

/**
 * Categorize transactions for IRS Schedule C deductions.
 *
 * @param {object[]}  transactions
 * @param {object}    [opts]
 * @param {string}    [opts.dateRangeStart]  ISO date (inclusive)
 * @param {string}    [opts.dateRangeEnd]    ISO date (inclusive)
 * @returns {{ lines: TaxSummaryLine[], totalDeductible: number, uncategorized: number }}
 */
function categorizeTaxes(transactions, opts = {}) {
  if (!Array.isArray(transactions)) throw new TypeError('transactions must be an array');

  const { dateRangeStart, dateRangeEnd } = opts;

  // Filter by date range
  const filtered = transactions.filter(t => {
    if (!t.date) return false;
    if (dateRangeStart && t.date < dateRangeStart) return false;
    if (dateRangeEnd && t.date > dateRangeEnd) return false;
    // Only expenses (negative amounts or expense-flagged)
    const amt = Number(t.amount);
    return amt < 0 || t.isExpense === true;
  });

  const lineMap = new Map(); // scheduleC → TaxSummaryLine
  let uncategorized = 0;

  for (const txn of filtered) {
    const rule = matchRule(txn);
    const amount = Math.abs(Number(txn.amount));

    if (!rule) {
      uncategorized++;
      continue;
    }

    if (!lineMap.has(rule.scheduleC)) {
      lineMap.set(rule.scheduleC, {
        scheduleC: rule.scheduleC,
        totalAmount: 0,
        deductibleAmount: 0,
        deductiblePct: rule.deductiblePct,
        transactionCount: 0,
      });
    }

    const line = lineMap.get(rule.scheduleC);
    line.totalAmount += amount;
    line.deductibleAmount += amount * rule.deductiblePct;
    line.transactionCount++;
  }

  const lines = Array.from(lineMap.values()).map(l => ({
    ...l,
    totalAmount: parseFloat(l.totalAmount.toFixed(2)),
    deductibleAmount: parseFloat(l.deductibleAmount.toFixed(2)),
  }));

  const totalDeductible = parseFloat(
    lines.reduce((s, l) => s + l.deductibleAmount, 0).toFixed(2),
  );

  return { lines, totalDeductible, uncategorized };
}

module.exports = { categorizeTaxes, SCHEDULE_C_RULES };
