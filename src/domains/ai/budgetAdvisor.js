'use strict';

/**
 * Budget Advisor
 * FIN-164: Compares current income to prior 3-month average and recommends
 * proportional budget adjustments.
 *
 * Pure function: no side effects, fully testable in isolation.
 *
 * IPC: ai:advise-budget
 * Payload: {
 *   currentMonthIncome: number,
 *   priorMonthlyIncomes: number[],    // Last 3 months (oldest first)
 *   budgetLimits: { category: string, limit: number }[],
 *   monthlyDebtMinPayments?: number,
 *   monthlyExpenses?: number
 * }
 */

/**
 * @typedef {object} BudgetRecommendation
 * @property {string}  category
 * @property {number}  currentLimit
 * @property {number}  recommendedLimit
 * @property {number}  delta            Positive = increase, negative = decrease
 * @property {string}  reason
 */

/**
 * @typedef {object} BudgetAdviceResult
 * @property {'stable'|'income_drop'|'income_rise'} incomeStatus
 * @property {number}  currentMonthIncome
 * @property {number}  priorAvgIncome
 * @property {number}  changePercent           Positive = rise, negative = drop
 * @property {BudgetRecommendation[]} recommendations
 * @property {string[]} actions                 High-level suggested actions
 */

const DROP_THRESHOLD = -0.15;   // -15%
const RISE_THRESHOLD = 0.15;    //  +15%

/**
 * Advise budget adjustments based on income changes.
 *
 * @param {object} params
 * @param {number} params.currentMonthIncome
 * @param {number[]} params.priorMonthlyIncomes     At least 1 prior month required
 * @param {{ category: string, limit: number }[]} params.budgetLimits
 * @param {number} [params.monthlyDebtMinPayments]
 * @param {number} [params.monthlyExpenses]         Total current expenses (excl. debt payments)
 * @returns {BudgetAdviceResult}
 */
function adviseBudget(params) {
  const {
    currentMonthIncome = 0,
    priorMonthlyIncomes = [],
    budgetLimits = [],
    monthlyDebtMinPayments = 0,
    monthlyExpenses = 0,
  } = params || {};

  if (!Array.isArray(priorMonthlyIncomes)) {
    throw new TypeError('priorMonthlyIncomes must be an array');
  }
  if (!Array.isArray(budgetLimits)) {
    throw new TypeError('budgetLimits must be an array');
  }

  // Use up to last 3 months
  const prior = priorMonthlyIncomes.slice(-3);
  const priorAvgIncome =
    prior.length > 0 ? prior.reduce((s, v) => s + Number(v), 0) / prior.length : 0;

  const changePercent =
    priorAvgIncome > 0
      ? parseFloat(((Number(currentMonthIncome) - priorAvgIncome) / priorAvgIncome).toFixed(4))
      : 0;

  let incomeStatus = 'stable';
  if (changePercent <= DROP_THRESHOLD) incomeStatus = 'income_drop';
  else if (changePercent >= RISE_THRESHOLD) incomeStatus = 'income_rise';

  const recommendations = [];
  const actions = [];

  if (incomeStatus === 'income_drop') {
    // Scale all budget limits proportionally by income change
    const scaleFactor = 1 + changePercent; // e.g. 0.85 for -15%
    for (const { category, limit } of budgetLimits) {
      const recommended = parseFloat((limit * scaleFactor).toFixed(2));
      recommendations.push({
        category,
        currentLimit: parseFloat(Number(limit).toFixed(2)),
        recommendedLimit: recommended,
        delta: parseFloat((recommended - limit).toFixed(2)),
        reason: `Income dropped ${Math.abs(changePercent * 100).toFixed(1)}% — scale proportionally`,
      });
    }
    actions.push('Review and confirm scaled budget limits');
    actions.push('Identify non-essential subscriptions to pause');
    actions.push('Delay any non-critical purchases until income recovers');
  } else if (incomeStatus === 'income_rise') {
    // Suggest increasing savings/debt payments by the income delta
    const incomeDelta = Number(currentMonthIncome) - priorAvgIncome;
    const savingsIncrease = parseFloat((incomeDelta * 0.5).toFixed(2)); // 50% of delta to savings
    const debtIncrease = parseFloat((incomeDelta * 0.3).toFixed(2));   // 30% of delta to debt

    actions.push(
      `Income rose ${(changePercent * 100).toFixed(1)}% — consider directing +$${savingsIncrease.toFixed(2)}/mo to savings`,
    );
    actions.push(
      `Apply +$${debtIncrease.toFixed(2)}/mo as extra debt payments to accelerate payoff`,
    );

    // Pass budget limits through unchanged but note the opportunity
    for (const { category, limit } of budgetLimits) {
      recommendations.push({
        category,
        currentLimit: parseFloat(Number(limit).toFixed(2)),
        recommendedLimit: parseFloat(Number(limit).toFixed(2)),
        delta: 0,
        reason: 'Income rise — maintain current limits and redirect surplus to goals/debt',
      });
    }
  } else {
    // Stable — pass through
    for (const { category, limit } of budgetLimits) {
      recommendations.push({
        category,
        currentLimit: parseFloat(Number(limit).toFixed(2)),
        recommendedLimit: parseFloat(Number(limit).toFixed(2)),
        delta: 0,
        reason: 'Income stable — no adjustment needed',
      });
    }
    actions.push('Income is stable — maintain current budget allocations');
  }

  return {
    incomeStatus,
    currentMonthIncome: parseFloat(Number(currentMonthIncome).toFixed(2)),
    priorAvgIncome: parseFloat(priorAvgIncome.toFixed(2)),
    changePercent,
    recommendations,
    actions,
  };
}

module.exports = { adviseBudget };
