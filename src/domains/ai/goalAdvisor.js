'use strict';

/**
 * Goal Advisor
 * FIN-164: Analyzes monthly surplus and advises on goal feasibility,
 * timeline acceleration, and spending reallocation opportunities.
 *
 * Pure function: no side effects, fully testable in isolation.
 *
 * IPC: ai:advise-goals
 * Payload: {
 *   goals: Goal[],
 *   monthlyIncome: number,
 *   monthlyExpenses: { category: string, amount: number }[],
 *   monthlyDebtMinPayments: number
 * }
 */

/**
 * @typedef {object} Goal
 * @property {string} id
 * @property {string} name
 * @property {number} targetAmount
 * @property {number} currentAmount
 * @property {number} [monthlyContribution]  Current monthly contribution toward goal
 */

/**
 * @typedef {object} GoalAdvice
 * @property {string}  goalId
 * @property {string}  goalName
 * @property {number}  remaining
 * @property {number|null} monthsAtCurrentPace  null if goal is unreachable
 * @property {string}  status                  'on_track' | 'underfunded' | 'complete'
 * @property {CategorySuggestion[]} suggestions
 */

/**
 * @typedef {object} CategorySuggestion
 * @property {string} category
 * @property {number} currentAmount
 * @property {number} suggestedReduction
 * @property {number} monthsSaved         Months shaved off goal completion
 */

/**
 * Categories generally considered discretionary (eligible for reduction suggestions).
 * @type {string[]}
 */
const DISCRETIONARY_CATEGORIES = [
  'dining', 'entertainment', 'shopping', 'subscriptions', 'hobbies',
  'personal care', 'clothing', 'travel', 'recreation', 'coffee', 'bars',
];

/**
 * Check if a spending category is discretionary.
 * @param {string} category
 * @returns {boolean}
 */
function isDiscretionary(category) {
  const c = (category || '').toLowerCase();
  return DISCRETIONARY_CATEGORIES.some(d => c.includes(d));
}

/**
 * Compute months to complete a goal given remaining amount and monthly surplus.
 * @param {number} remaining
 * @param {number} monthlyContribution
 * @returns {number|null}
 */
function monthsToComplete(remaining, monthlyContribution) {
  if (remaining <= 0) return 0;
  if (monthlyContribution <= 0) return null;
  return Math.ceil(remaining / monthlyContribution);
}

/**
 * Generate spending-reduction suggestions that would accelerate a goal.
 *
 * @param {number} remaining         Amount still needed for goal
 * @param {number} currentMonths     Months at current pace (or null)
 * @param {{ category: string, amount: number }[]} expenses
 * @param {number} reductionFraction Fraction of each category to suggest cutting (default 0.2)
 * @returns {CategorySuggestion[]}
 */
function buildSuggestions(remaining, currentMonths, expenses, reductionFraction = 0.2) {
  const discretionary = expenses.filter(e => isDiscretionary(e.category) && e.amount > 0);

  return discretionary
    .map(e => {
      const reduction = parseFloat((e.amount * reductionFraction).toFixed(2));
      if (reduction <= 0) return null;

      const newMonths = monthsToComplete(remaining, reduction);
      const monthsSaved =
        currentMonths != null && newMonths != null ? Math.max(0, currentMonths - newMonths) : 0;

      return {
        category: e.category,
        currentAmount: parseFloat(e.amount.toFixed(2)),
        suggestedReduction: reduction,
        monthsSaved,
      };
    })
    .filter(Boolean)
    .sort((a, b) => b.monthsSaved - a.monthsSaved)
    .slice(0, 3); // Top 3 suggestions per goal
}

/**
 * Advise on goal feasibility and acceleration for each goal.
 *
 * @param {object} params
 * @param {Goal[]} params.goals
 * @param {number} params.monthlyIncome
 * @param {{ category: string, amount: number }[]} params.monthlyExpenses
 * @param {number} [params.monthlyDebtMinPayments]
 * @returns {{ surplus: number, goalAdvice: GoalAdvice[] }}
 */
function adviseGoals(params) {
  const {
    goals = [],
    monthlyIncome = 0,
    monthlyExpenses = [],
    monthlyDebtMinPayments = 0,
  } = params || {};

  if (!Array.isArray(goals)) throw new TypeError('goals must be an array');
  if (!Array.isArray(monthlyExpenses)) throw new TypeError('monthlyExpenses must be an array');

  const totalExpenses = monthlyExpenses.reduce((s, e) => s + (Number(e.amount) || 0), 0);
  const surplus = Number(monthlyIncome) - totalExpenses - Number(monthlyDebtMinPayments);

  // Distribute surplus evenly across goals if no explicit contribution is set
  const goalContribution =
    goals.length > 0 && surplus > 0 ? surplus / goals.length : 0;

  const goalAdvice = goals.map(goal => {
    const remaining = Math.max(0, Number(goal.targetAmount) - Number(goal.currentAmount));
    const contribution = Number(goal.monthlyContribution) || goalContribution;

    let status;
    let months;

    if (remaining <= 0) {
      status = 'complete';
      months = 0;
    } else if (contribution <= 0) {
      status = 'underfunded';
      months = null;
    } else {
      months = monthsToComplete(remaining, contribution);
      status = months != null && months <= 120 ? 'on_track' : 'underfunded';
    }

    const suggestions =
      remaining > 0
        ? buildSuggestions(remaining, months, monthlyExpenses)
        : [];

    return {
      goalId: goal.id,
      goalName: goal.name,
      remaining: parseFloat(remaining.toFixed(2)),
      monthsAtCurrentPace: months,
      status,
      suggestions,
    };
  });

  return {
    surplus: parseFloat(surplus.toFixed(2)),
    goalAdvice,
  };
}

module.exports = { adviseGoals };
