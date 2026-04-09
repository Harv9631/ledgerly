'use strict';

/**
 * Ingestion Queue
 * Async pipeline that processes transactions without blocking transaction writes.
 * Emits 'processed' and 'error' events.
 *
 * Throughput target: 1,000 transactions/minute on a single worker.
 * At ~50ms per transaction (normalization + extraction + storage), a single
 * worker handles ~1,200 txn/min with head-room.
 */

const { EventEmitter } = require('events');

class IngestionQueue extends EventEmitter {
  /**
   * @param {object} opts
   * @param {Function} opts.processor  async (item) => void  — the pipeline function
   * @param {number}   [opts.concurrency=4]
   */
  constructor({ processor, concurrency = 4 } = {}) {
    super();
    if (typeof processor !== 'function') throw new TypeError('processor must be a function');
    this._processor   = processor;
    this._concurrency = concurrency;
    this._queue       = [];
    this._active      = 0;
    this._running     = false;
  }

  /** Start accepting and processing items. */
  start() {
    this._running = true;
    this._drain();
    return this;
  }

  /** Stop accepting new items. In-flight items complete normally. */
  stop() {
    this._running = false;
    return this;
  }

  /**
   * Add a transaction to the pipeline.
   * @param {object} transaction  Raw Plaid transaction
   * @param {object} [context={}] Account context for feature extraction
   */
  enqueue(transaction, context = {}) {
    if (!transaction || !transaction.transaction_id) {
      this._logError(new TypeError('enqueue: transaction must have transaction_id'), null);
      return;
    }
    this._queue.push({ transaction, context });
    if (this._running) this._drain();
  }

  /** Current queue depth (pending items). */
  get depth() { return this._queue.length; }

  // ── Private ──────────────────────────────────────────────────────

  _drain() {
    while (this._active < this._concurrency && this._queue.length > 0) {
      const item = this._queue.shift();
      this._active++;
      this._process(item);
    }
  }

  async _process(item) {
    try {
      const result = await this._processor(item);
      this.emit('processed', { transaction_id: item.transaction.transaction_id, result });
    } catch (err) {
      this._logError(err, item.transaction.transaction_id);
      this.emit('error', { transaction_id: item.transaction.transaction_id, error: err });
    } finally {
      this._active--;
      if (this._running) this._drain();
    }
  }

  _logError(err, transaction_id) {
    // Log to existing error tracking (console.error in Electron main process
    // — swap for your error tracking service as needed)
    console.error('[IngestionQueue] error', {
      transaction_id,
      message: err?.message,
      stack:   err?.stack,
    });
  }
}

module.exports = { IngestionQueue };
