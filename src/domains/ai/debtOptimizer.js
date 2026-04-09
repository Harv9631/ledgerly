'use strict';

/**
 * Debt Payoff Optimizer
 * FIN-137: Calculates avalanche and snowball payoff schedules.
 *
 * Avalanche strategy: pay minimums on all debts, apply extra to highest-APR first.
 * Snowball strategy:  pay minimums on all debts, apply extra to lowest-balance first.
 *
 * Output: month-by-month schedule, total interest paid, and payoff date per strategy.
 *
 * IPC endpoint: ai:debt-optimizer  (analogous to POST /api/ai/debt-optimizer)
 */

/**
 * Validate and normalize an individual debt entry.
 *
 * @param {object} debt
 * @param {number} debt.balance       Current balance (> 0)
 * @param {number} debt.apr           Annual percentage rate as a decimal (e.g. 0.1999 for 19.99%)
 * @param {number} debt.minPayment    Minimum monthly payment (> 0)
 * @param {string} [debt.name]        Label (optional)
 * @returns {object}
 */
function normalizeDebt(debt, index) {
  if (!debt || typeof debt !== 'object') throw new TypeError(`debt[${index}] must be an object`);
  const balance = Number(debt.balance);
  const apr = Number(debt.apr);
  const minPayment = Number(debt.minPayment);
  if (!Number.isFinite(balance) || balance <= 0) throw new RangeError(`debt[${index}].balance must be > 0`);
  if (!Number.isFinite(apr) || apr < 0) throw new RangeError(`debt[${index}].apr must be >= 0`);
  if (!Number.isFinite(minPayment) || minPayment <= 0) throw new RangeError(`debt[${index}].minPayment must be > 0`);
  return {
    id:         index,
    name:       debt.name ?? `Debt ${index + 1}`,
    balance:    parseFloat(balance.toFixed(2)),
    apr,
    monthlyRate: apr / 12,
    minPayment: parseFloat(minPayment.toFixed(2)),
  };
}

/**
 * Run a single month of payments across all debts under a chosen strategy.
 *
 * @param {object[]} debts           Mutable array of normalized debt objects
 * @param {number}   extraPayment    Extra cash to apply this month (after all minimums)
 * @param {Function} priorityFn     (debts) => debt  — picks the target for extra payment
 * @returns {{ paid: number, interest: number }}
 */
function runMonth(debts, extraPayment, priorityFn) {
  let totalInterest = 0;
  let totalPaid = 0;

  // 1. Accrue interest on all active debts
  for (const d of debts) {
    if (d.balance <= 0) continue;
    const interest = parseFloat((d.balance * d.monthlyRate).toFixed(2));
    d.balance = parseFloat((d.balance + interest).toFixed(2));
    totalInterest += interest;
  }

  // 2. Pay minimums
  for (const d of debts) {
    if (d.balance <= 0) continue;
    const payment = Math.min(d.minPayment, d.balance);
    d.balance = parseFloat(Math.max(0, d.balance - payment).toFixed(2));
    totalPaid += payment;
  }

  // 3. Apply extra to the priority debt
  let remaining = extraPayment;
  while (remaining > 0) {
    const activeDebts = debts.filter(d => d.balance > 0);
    if (activeDebts.length === 0) break;
    const target = priorityFn(activeDebts);
    const payment = Math.min(remaining, target.balance);
    target.balance = parseFloat(Math.max(0, target.balance - payment).toFixed(2));
    totalPaid += payment;
    remaining -= payment;
  }

  return { paid: parseFloat(totalPaid.toFixed(2)), interest: parseFloat(totalInterest.toFixed(2)) };
}

/**
 * Simulate payoff schedule to completion (or MAX_MONTHS safety limit).
 *
 * @param {object[]} initialDebts     Normalized debt array (will be deep-cloned)
 * @param {number}   extraPayment     Extra monthly payment (>= 0)
 * @param {Function} priorityFn      Strategy function
 * @param {number}   [maxMonths=600] Safety cap (50 years)
 * @returns {PayoffResult}
 *
 * @typedef {object} MonthSnapshot
 * @property {number} month
 * @property {number} totalBalance
 * @property {number} interestPaid
 * @property {number} principalPaid
 * @property {DebtSnapshot[]} debts
 *
 * @typedef {object} DebtSnapshot
 * @property {number} id
 * @property {string} name
 * @property {number} balance
 *
 * @typedef {object} PayoffResult
 * @property {MonthSnapshot[]} schedule
 * @property {number} totalInterestPaid
 * @property {number} totalPaid
 * @property {number} monthsToPayoff
 * @property {string} payoffDate          ISO month "YYYY-MM"
 */
function simulate(initialDebts, extraPayment, priorityFn, maxMonths = 600) {
  // Deep clone so we don't mutate caller's data
  const debts = initialDebts.map(d => ({ ...d }));

  const schedule = [];
  let totalInterestPaid = 0;
  let totalPaid = 0;

  const startDate = new Date();
  startDate.setDate(1);

  for (let month = 1; month <= maxMonths; month++) {
    const balanceBefore = debts.reduce((s, d) => s + d.balance, 0);
    if (balanceBefore <= 0) break;

    const { paid, interest } = runMonth(debts, extraPayment, priorityFn);
    totalInterestPaid += interest;
    totalPaid += paid;

    const balanceAfter = debts.reduce((s, d) => s + d.balance, 0);

    schedule.push({
      month,
      totalBalance:  parseFloat(Math.max(0, balanceAfter).toFixed(2)),
      interestPaid:  parseFloat(interest.toFixed(2)),
      principalPaid: parseFloat((paid - interest).toFixed(2)),
      debts: debts.map(d => ({ id: d.id, name: d.name, balance: d.balance })),
    });

    if (balanceAfter <= 0) break;
  }

  const payoffMonths = schedule.length;
  const payoffDate = new Date(startDate);
  payoffDate.setMonth(payoffDate.getMonth() + payoffMonths);
  const payoffIso = `${payoffDate.getFullYear()}-${String(payoffDate.getMonth() + 1).padStart(2, '0')}`;

  return {
    schedule,
    totalInterestPaid: parseFloat(totalInterestPaid.toFixed(2)),
    totalPaid:         parseFloat(totalPaid.toFixed(2)),
    monthsToPayoff:    payoffMonths,
    payoffDate:        payoffIso,
  };
}

// ── Strategy selectors ────────────────────────────────────────────────────────

const avalanchePriority = debts =>
  debts.reduce((best, d) => (d.apr > best.apr ? d : best), debts[0]);

const snowballPriority = debts =>
  debts.reduce((best, d) => (d.balance < best.balance ? d : best), debts[0]);

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Calculate avalanche and snowball payoff plans.
 *
 * @param {object}   input
 * @param {object[]} input.debts          Array of debt objects (see normalizeDebt)
 * @param {number}   [input.extraPayment] Additional monthly payment beyond minimums; default 0
 * @returns {OptimizerOutput}
 *
 * @typedef {object} OptimizerOutput
 * @property {PayoffResult} avalanche
 * @property {PayoffResult} snowball
 * @property {object}       comparison
 * @property {number}       comparison.interestSavedByAvalanche  vs snowball
 * @property {number}       comparison.monthsSavedByAvalanche    vs snowball
 */
function optimizeDebtPayoff(input) {
  if (!input || !Array.isArray(input.debts)) throw new TypeError('input.debts must be an array');
  if (input.debts.length === 0) throw new RangeError('input.debts must not be empty');

  const extraPayment = Math.max(0, Number(input.extraPayment ?? 0));
  const normalizedDebts = input.debts.map((d, i) => normalizeDebt(d, i));

  const avalanche = simulate(normalizedDebts, extraPayment, avalanchePriority);
  const snowball  = simulate(normalizedDebts, extraPayment, snowballPriority);

  return {
    avalanche,
    snowball,
    comparison: {
      interestSavedByAvalanche: parseFloat((snowball.totalInterestPaid - avalanche.totalInterestPaid).toFixed(2)),
      monthsSavedByAvalanche:   snowball.monthsToPayoff - avalanche.monthsToPayoff,
    },
  };
}

module.exports = {
  optimizeDebtPayoff,
  // Exported for testing
  normalizeDebt,
  simulate,
  avalanchePriority,
  snowballPriority,
};
