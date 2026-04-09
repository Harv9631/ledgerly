'use strict';

/**
 * Pipeline Orchestrator
 * Wires normalization → feature extraction → storage.
 *
 * The storage interface is intentionally minimal so callers can plug in
 * a real Postgres client (pg), an in-memory store for tests, or a file adapter.
 *
 * Storage interface:
 *   storage.saveFeatures(featureRow: object): Promise<void>
 *   storage.loadTransactions(): Promise<Transaction[]>     (for reprocessing)
 *   storage.loadAccountContext(accountId: string): Promise<object>
 */

const { extractFeatures } = require('./featureExtractor');

/**
 * Process a single transaction through the full pipeline.
 *
 * @param {object}   txn      Raw Plaid transaction
 * @param {object}   ctx      Account context ({ accountType, accountMean90d, ... })
 * @param {object}   storage  Storage adapter
 * @returns {Promise<object>} The extracted feature row
 */
async function processSingle(txn, ctx, storage) {
  const features = extractFeatures(txn, ctx);
  if (storage && typeof storage.saveFeatures === 'function') {
    await storage.saveFeatures(features);
  }
  return features;
}

/**
 * Processor function compatible with IngestionQueue.
 * Accepts the {transaction, context} item shape the queue delivers.
 *
 * @param {object} item
 * @param {object} storage
 * @returns {Function} async ({ transaction, context }) => feature row
 */
function makeQueueProcessor(storage) {
  return ({ transaction, context }) => processSingle(transaction, context, storage);
}

/**
 * Reprocess (backfill) all existing transactions.
 * Fetches transactions and account contexts from storage, runs them through
 * the pipeline sequentially to avoid overwhelming the process.
 *
 * @param {object}   storage
 * @param {object}   [opts]
 * @param {Function} [opts.onProgress]  (done, total) => void
 * @param {number}   [opts.batchSize=100]
 * @returns {Promise<{ processed: number, errors: number }>}
 */
async function reprocessAll(storage, opts = {}) {
  const { onProgress, batchSize = 100 } = opts;

  if (typeof storage.loadTransactions !== 'function') {
    throw new TypeError('storage.loadTransactions must be a function');
  }

  const transactions = await storage.loadTransactions();
  const total = transactions.length;
  let processed = 0;
  let errors = 0;

  // Process in batches to stay within memory budget
  for (let i = 0; i < transactions.length; i += batchSize) {
    const batch = transactions.slice(i, i + batchSize);
    await Promise.all(batch.map(async txn => {
      try {
        let ctx = {};
        if (typeof storage.loadAccountContext === 'function') {
          ctx = await storage.loadAccountContext(txn.account_id) ?? {};
        }
        await processSingle(txn, ctx, storage);
        processed++;
      } catch (err) {
        errors++;
        console.error('[pipeline] reprocess error', {
          transaction_id: txn.transaction_id,
          message: err?.message,
        });
      }
    }));
    if (onProgress) onProgress(Math.min(i + batchSize, total), total);
  }

  return { processed, errors };
}

module.exports = { processSingle, makeQueueProcessor, reprocessAll };
