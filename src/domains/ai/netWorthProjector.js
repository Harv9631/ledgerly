'use strict';

/**
 * Net Worth Projector
 * FIN-164: Projects net worth month-by-month for 12, 36, and 60 months,
 * integrating with existing debtOptimizer.js payoff schedules.
 *
 * Pure function: no side effects, fully testable in isolation.
 *
 * IPC: ai:project-net-worth
 * Payload: {
 *   assets: number,
 *   debts: Debt[],
 *   monthlyIncome: number,
 *   monthlyExpenses: number,
 *   monthlySavingsRate: number,  // fraction 0–1
 *   annualIncomeGrowthPct: number, // e.g. 0.03 for 3%
 *   horizonMonths?: number[]     // default [12, 36, 60]
 * }
 */

const { optimizeDebtPayoff } = require('./debtOptimizer');

/**
 * @typedef {object} MonthlySnapshot
 * @property {number} month          1-based month index
 * @property {number} assets
 * @property {number} remainingDebt
 * @property {number} netWorth
 */

/**
 * @typedef {object} ProjectionResult
 * @property {MonthlySnapshot[]} monthly
 * @property {{ months: number, netWorth: number }[]} summaries
 * @property {number} initialNetWorth
 */

/**
 * Project net worth over time.
 *
 * @param {object} params
 * @param {number} params.assets                Current total assets value
 * @param {object[]} params.debts               Debt objects (balance, apr, minPayment, name?)
 * @param {number} params.monthlyIncome         Current gross monthly income
 * @param {number} params.monthlyExpenses       Current monthly expenses (excl. debt payments)
 * @param {number} [params.monthlySavingsRate]  Fraction of surplus to save (default 0.2)
 * @param {number} [params.annualIncomeGrowthPct] Annual income growth rate (default 0)
 * @param {number[]} [params.horizonMonths]     Horizons to summarize (default [12,36,60])
 * @returns {ProjectionResult}
 */
function projectNetWorth(params) {
  const {
    assets = 0,
    debts = [],
    monthlyIncome = 0,
    monthlyExpenses = 0,
    monthlySavingsRate = 0.2,
    annualIncomeGrowthPct = 0,
    horizonMonths = [12, 36, 60],
  } = params || {};

  if (typeof assets !== 'number') throw new TypeError('assets must be a number');
  if (!Array.isArray(debts)) throw new TypeError('debts must be an array');

  const maxMonths = Math.max(...horizonMonths, 0);

  // Get debt payoff schedules from existing optimizer
  let debtSchedule = null;
  let totalMinPayments = 0;

  if (debts.length > 0) {
    try {
      const result = optimizeDebtPayoff({ debts, extraPayment: 0 });
      // Use avalanche as default (lower total interest)
      debtSchedule = result.avalanche?.schedule ?? null;
      totalMinPayments = debts.reduce((s, d) => s + (Number(d.minPayment) || 0), 0);
    } catch {
      // If debt optimizer fails, fall back to simple min payment tracking
      totalMinPayments = debts.reduce((s, d) => s + (Number(d.minPayment) || 0), 0);
    }
  }

  // Build month-by-month totals for remaining debt from the schedule
  const remainingDebtByMonth = new Map();
  if (debtSchedule && Array.isArray(debtSchedule)) {
    for (const entry of debtSchedule) {
      const month = entry.month ?? entry.monthIndex;
      if (month != null) {
        remainingDebtByMonth.set(month, entry.totalBalance ?? entry.remainingBalance ?? 0);
      }
    }
  }

  // If no debt schedule, compute simple linear payoff
  const computeFallbackDebt = monthIndex => {
    const totalDebt = debts.reduce((s, d) => s + (Number(d.balance) || 0), 0);
    if (totalMinPayments <= 0 || totalDebt <= 0) return 0;
    const monthsToPay = Math.ceil(totalDebt / totalMinPayments);
    return Math.max(0, totalDebt - monthIndex * totalMinPayments);
  };

  const monthlyGrowthFactor = 1 + annualIncomeGrowthPct / 12;
  let currentAssets = Number(assets);
  let currentIncome = Number(monthlyIncome);
  const snapshots = [];

  for (let m = 1; m <= maxMonths; m++) {
    // Income grows each month by growth factor
    currentIncome *= monthlyGrowthFactor;

    const surplus = currentIncome - monthlyExpenses - totalMinPayments;
    const savings = surplus > 0 ? surplus * monthlySavingsRate : 0;
    currentAssets += savings;

    const remainingDebt = remainingDebtByMonth.has(m)
      ? remainingDebtByMonth.get(m)
      : computeFallbackDebt(m);

    snapshots.push({
      month: m,
      assets: parseFloat(currentAssets.toFixed(2)),
      remainingDebt: parseFloat(Math.max(0, remainingDebt).toFixed(2)),
      netWorth: parseFloat((currentAssets - Math.max(0, remainingDebt)).toFixed(2)),
    });
  }

  const initialDebt = debts.reduce((s, d) => s + (Number(d.balance) || 0), 0);
  const initialNetWorth = parseFloat((Number(assets) - initialDebt).toFixed(2));

  const summaries = horizonMonths.map(months => ({
    months,
    netWorth: snapshots[months - 1]?.netWorth ?? initialNetWorth,
  }));

  return { monthly: snapshots, summaries, initialNetWorth };
}

module.exports = { projectNetWorth };
