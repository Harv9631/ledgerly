'use strict';

/**
 * AI Domain — Electron IPC wiring
 * Registers IPC handlers:
 *   ai:queue-transaction    → enqueue a single transaction for async processing
 *   ai:reprocess            → POST /api/ai/reprocess: backfill all stored transactions
 *   ai:detect-trends        → run trend detection against a transaction set
 *   ai:analyze-transaction  → run anomaly detection on a single transaction
 *   ai:debt-optimizer       → POST /api/ai/debt-optimizer: payoff plan calculation
 *   ai:forecast-cashflow    → project cash flow for 30/60/90 days
 *   ai:detect-subscriptions → detect recurring charges and duplicates
 *   ai:categorize-taxes     → map transactions to IRS Schedule C (business mode)
 *   ai:project-net-worth    → project net worth for 12/36/60 months
 *   ai:advise-goals         → advise on goal feasibility and acceleration
 *   ai:parse-search-query   → NL transaction search via Claude (haiku)
 *   ai:advise-budget        → adaptive budget recommendations based on income changes
 *   ai:suggest-mileage      → generate mileage log suggestions (business mode)
 *
 * Call registerIpcHandlers(ipcMain, storage) once from electron-main.js.
 */

const { IngestionQueue } = require('./ingestionQueue');
const { makeQueueProcessor, reprocessAll } = require('./pipeline');
const { detectTrends } = require('./trendDetection');
const { analyzeTransaction, pushAlerts } = require('./anomalyAlerts');
const { optimizeDebtPayoff } = require('./debtOptimizer');
const { forecastCashFlow } = require('./cashFlowForecaster');
const { detectSubscriptions } = require('./subscriptionDetector');
const { categorizeTaxes } = require('./taxCategorizer');
const { projectNetWorth } = require('./netWorthProjector');
const { adviseGoals } = require('./goalAdvisor');
const { adviseBudget } = require('./budgetAdvisor');
const { suggestMileage } = require('./mileageSuggestor');
const Anthropic = require('@anthropic-ai/sdk');

/** In-memory notification queue (push alerts here; renderer polls via ai:get-alerts). */
const _alertQueue = [];

/** Singleton queue — initialized once per process. */
let _queue = null;

/**
 * Build a minimal file-based storage adapter from the existing Electron
 * JSON file store (plaid items store).  Swap this for a real pg adapter
 * once Postgres is available.
 *
 * @param {object} opts
 * @param {Function} opts.readTransactions  () => Transaction[]  (sync or async)
 * @returns {object} storage adapter
 */
function makeFileStorage({ readTransactions } = {}) {
  const features = new Map(); // in-memory feature cache

  return {
    async saveFeatures(row) {
      features.set(row.transaction_id, row);
      // No persistent write here — Phase 2 will swap this for pg INSERT
    },

    getFeatures(transactionId) {
      return features.get(transactionId) ?? null;
    },

    getAllFeatures() {
      return Array.from(features.values());
    },

    clearFeatures() {
      features.clear();
    },

    async loadTransactions() {
      if (typeof readTransactions !== 'function') return [];
      const result = await readTransactions();
      return Array.isArray(result) ? result : [];
    },

    async loadAccountContext(_accountId) {
      // No account history available yet — return empty context
      return {};
    },
  };
}

/**
 * Register AI IPC handlers on the provided ipcMain instance.
 *
 * @param {object} ipcMain   Electron ipcMain
 * @param {object} storage   Storage adapter (see makeFileStorage)
 */
function registerIpcHandlers(ipcMain, storage) {
  if (_queue) return; // idempotent

  _queue = new IngestionQueue({
    processor: makeQueueProcessor(storage),
    concurrency: 4,
  });

  _queue.on('error', ({ transaction_id, error }) => {
    console.error('[AI] pipeline error', { transaction_id, message: error?.message });
  });

  _queue.start();

  /** Enqueue a single transaction from the renderer for async processing. */
  ipcMain.handle('ai:queue-transaction', async (_event, { transaction, context = {} } = {}) => {
    try {
      if (!transaction || !transaction.transaction_id) {
        return { error: 'transaction.transaction_id is required' };
      }
      _queue.enqueue(transaction, context);
      return { queued: true, queueDepth: _queue.depth };
    } catch (err) {
      return { error: err.message };
    }
  });

  /** Reprocess all stored transactions — backfill feature store. */
  ipcMain.handle('ai:reprocess', async (_event, opts = {}) => {
    try {
      const result = await reprocessAll(storage, {
        batchSize: opts.batchSize ?? 100,
      });
      return { ok: true, ...result };
    } catch (err) {
      return { error: err.message };
    }
  });

  /** Expose current in-memory feature store (dev/debug). */
  ipcMain.handle('ai:get-features', async (_event, transactionId) => {
    try {
      return transactionId
        ? storage.getFeatures(transactionId)
        : storage.getAllFeatures();
    } catch (err) {
      return { error: err.message };
    }
  });

  /**
   * Trend detection — scheduled daily or on-demand.
   * Payload: { transactions: Transaction[], currentMonth?: "YYYY-MM", deviationThreshold?: number }
   */
  ipcMain.handle('ai:detect-trends', async (_event, payload = {}) => {
    try {
      const { transactions = [], ...opts } = payload;
      const trends = detectTrends(transactions, opts);
      return { ok: true, trends };
    } catch (err) {
      return { error: err.message };
    }
  });

  /**
   * Anomaly detection — triggered on each transaction write.
   * Payload: { transaction, merchantHistory?, incomeTransactions?, recentDebtTxns?, opts? }
   */
  ipcMain.handle('ai:analyze-transaction', async (_event, payload = {}) => {
    try {
      const { transaction, ...ctx } = payload;
      if (!transaction?.transaction_id) return { error: 'transaction.transaction_id is required' };
      const alerts = analyzeTransaction(transaction, ctx);
      pushAlerts(alerts, { push: a => _alertQueue.push(a) });
      return { ok: true, alerts };
    } catch (err) {
      return { error: err.message };
    }
  });

  /** Retrieve and drain the pending alert queue. */
  ipcMain.handle('ai:get-alerts', async () => {
    const alerts = _alertQueue.splice(0);
    return { alerts };
  });

  /**
   * Debt payoff optimizer — POST /api/ai/debt-optimizer equivalent.
   * Payload: { debts: [{ balance, apr, minPayment, name? }], extraPayment?: number }
   */
  ipcMain.handle('ai:debt-optimizer', async (_event, payload = {}) => {
    try {
      const result = optimizeDebtPayoff(payload);
      return { ok: true, ...result };
    } catch (err) {
      return { error: err.message };
    }
  });

  /**
   * Cash flow forecaster.
   * Payload: { transactions: Transaction[], currentBalance?: number, forecastDays?: number[] }
   */
  ipcMain.handle('ai:forecast-cashflow', async (_event, payload = {}) => {
    try {
      const { transactions = [], ...opts } = payload;
      const result = forecastCashFlow(transactions, opts);
      return { ok: true, ...result };
    } catch (err) {
      return { error: err.message };
    }
  });

  /**
   * Subscription detector.
   * Payload: { transactions: Transaction[], minConfidence?: number, minOccurrences?: number }
   */
  ipcMain.handle('ai:detect-subscriptions', async (_event, payload = {}) => {
    try {
      const { transactions = [], ...opts } = payload;
      const result = detectSubscriptions(transactions, opts);
      return { ok: true, ...result };
    } catch (err) {
      return { error: err.message };
    }
  });

  /**
   * Tax categorizer (business mode).
   * Payload: { transactions: Transaction[], dateRangeStart?: string, dateRangeEnd?: string }
   */
  ipcMain.handle('ai:categorize-taxes', async (_event, payload = {}) => {
    try {
      const { transactions = [], ...opts } = payload;
      const result = categorizeTaxes(transactions, opts);
      return { ok: true, ...result };
    } catch (err) {
      return { error: err.message };
    }
  });

  /**
   * Net worth projector.
   * Payload: { assets, debts, monthlyIncome, monthlyExpenses, monthlySavingsRate?,
   *            annualIncomeGrowthPct?, horizonMonths? }
   */
  ipcMain.handle('ai:project-net-worth', async (_event, payload = {}) => {
    try {
      const result = projectNetWorth(payload);
      return { ok: true, ...result };
    } catch (err) {
      return { error: err.message };
    }
  });

  /**
   * Goal advisor.
   * Payload: { goals, monthlyIncome, monthlyExpenses, monthlyDebtMinPayments? }
   */
  ipcMain.handle('ai:advise-goals', async (_event, payload = {}) => {
    try {
      const result = adviseGoals(payload);
      return { ok: true, ...result };
    } catch (err) {
      return { error: err.message };
    }
  });

  /**
   * NL transaction search — sends user query to Claude (haiku) and returns a structured filter.
   * Payload: { query: string, transactionSchema?: object }
   */
  ipcMain.handle('ai:parse-search-query', async (_event, payload = {}) => {
    try {
      const { query, transactionSchema } = payload;
      if (!query || typeof query !== 'string') return { error: 'query string is required' };

      const client = new Anthropic();
      const schemaHint = transactionSchema
        ? `\nTransaction fields available: ${JSON.stringify(transactionSchema)}`
        : '\nTransaction fields: date (YYYY-MM-DD), amount (negative=expense), merchant_name, category, account_id';

      const message = await client.messages.create({
        model: 'claude-haiku-4-5',
        max_tokens: 512,
        messages: [
          {
            role: 'user',
            content:
              `Parse this transaction search query into a structured JSON filter object.${schemaHint}\n\n` +
              `Return ONLY valid JSON with these optional fields: ` +
              `{ minAmount, maxAmount, merchant, category, startDate, endDate, isRecurring, accountId }.\n\n` +
              `Query: "${query}"`,
          },
        ],
      });

      const text = message.content[0]?.text ?? '';
      // Extract JSON from the response
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (!jsonMatch) return { ok: true, filter: {}, rawResponse: text };

      const filter = JSON.parse(jsonMatch[0]);
      return { ok: true, filter, query };
    } catch (err) {
      return { error: err.message };
    }
  });

  /**
   * Budget advisor — adaptive budget recommendations based on income changes.
   * Payload: { currentMonthIncome, priorMonthlyIncomes, budgetLimits,
   *            monthlyDebtMinPayments?, monthlyExpenses? }
   */
  ipcMain.handle('ai:advise-budget', async (_event, payload = {}) => {
    try {
      const result = adviseBudget(payload);
      return { ok: true, ...result };
    } catch (err) {
      return { error: err.message };
    }
  });

  /**
   * Mileage suggestor (business mode).
   * Payload: { transactions: Transaction[], businessKeywords?: string[], irsRate?: number }
   */
  ipcMain.handle('ai:suggest-mileage', async (_event, payload = {}) => {
    try {
      const { transactions = [], ...opts } = payload;
      const result = suggestMileage(transactions, opts);
      return { ok: true, ...result };
    } catch (err) {
      return { error: err.message };
    }
  });
}

/** Gracefully stop the queue (call on app quit). */
function shutdown() {
  if (_queue) {
    _queue.stop();
    _queue = null;
  }
}

module.exports = {
  registerIpcHandlers,
  makeFileStorage,
  shutdown,
};
