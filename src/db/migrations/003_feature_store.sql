-- Migration: 003_feature_store
-- Description: ML feature vectors per transaction.
--              Extracted by the data ingestion pipeline (FIN-134).
--              Versioned so schema can evolve without reprocessing old data.
--              Phase 3 LLM embedding column included but nullable.

BEGIN;

CREATE TABLE IF NOT EXISTS transaction_features (
  id                          SERIAL  PRIMARY KEY,
  transaction_id              VARCHAR(255) NOT NULL
                                REFERENCES transactions(transaction_id) ON DELETE CASCADE,
  feature_version             SMALLINT NOT NULL DEFAULT 1,  -- bump when feature set changes

  -- ── Numeric / amount features ──────────────────────────────────
  amount_abs                  DECIMAL(14,2),                -- abs(amount)
  amount_log                  DECIMAL(14,6),                -- log1p(abs(amount)) for normalization
  amount_z_score              DECIMAL(10,6),                -- z-score vs account 90-day mean

  -- ── Temporal features ──────────────────────────────────────────
  day_of_week                 SMALLINT                      -- 0=Mon … 6=Sun
                                CHECK (day_of_week BETWEEN 0 AND 6),
  day_of_month                SMALLINT
                                CHECK (day_of_month BETWEEN 1 AND 31),
  month_of_year               SMALLINT
                                CHECK (month_of_year BETWEEN 1 AND 12),
  quarter                     SMALLINT
                                CHECK (quarter BETWEEN 1 AND 4),
  is_weekend                  BOOLEAN,
  is_month_start              BOOLEAN,                      -- day_of_month <= 5
  is_month_end                BOOLEAN,                      -- day_of_month >= 25

  -- ── Merchant features ──────────────────────────────────────────
  merchant_name_normalized    VARCHAR(255),                 -- lowercase, stripped punctuation
  payment_channel_enc         SMALLINT,                     -- 0=online, 1=in_store, 2=other
  has_merchant_id             BOOLEAN,                      -- Plaid merchant_id present

  -- ── Recurrence features ────────────────────────────────────────
  is_recurring                BOOLEAN  DEFAULT FALSE,
  recurrence_period_days      SMALLINT,                     -- e.g. 30 for monthly subscriptions
  recurrence_confidence       DECIMAL(5,4)
                                CHECK (recurrence_confidence IS NULL
                                  OR (recurrence_confidence >= 0 AND recurrence_confidence <= 1)),

  -- ── Account-context features ───────────────────────────────────
  account_type_enc            SMALLINT,                     -- 0=depository, 1=credit, 2=loan, 3=investment
  running_balance_before      DECIMAL(14,2),                -- account balance before this txn

  -- ── Plaid category hints (one-hot friendly) ────────────────────
  plaid_category_l0           VARCHAR(100),                 -- top-level Plaid category
  plaid_category_l1           VARCHAR(100),                 -- mid-level
  plaid_category_l2           VARCHAR(100),                 -- leaf-level

  -- ── Phase 3 LLM context cache (nullable until Phase 3) ─────────
  -- Sentence embedding of transaction.name, dim=1536 (text-embedding-3-small)
  -- Store as JSONB array for Phase 2 compatibility; swap to pgvector in Phase 3.
  name_embedding              JSONB,                        -- [float, …] length 1536

  -- ── Metadata ──────────────────────────────────────────────────
  computed_at                 TIMESTAMP DEFAULT NOW(),
  created_at                  TIMESTAMP DEFAULT NOW(),
  updated_at                  TIMESTAMP DEFAULT NOW(),

  UNIQUE (transaction_id, feature_version)
);

CREATE INDEX IF NOT EXISTS idx_features_transaction
  ON transaction_features(transaction_id);

CREATE INDEX IF NOT EXISTS idx_features_version
  ON transaction_features(feature_version);

CREATE INDEX IF NOT EXISTS idx_features_recurring
  ON transaction_features(is_recurring) WHERE is_recurring = TRUE;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_features_updated_at'
  ) THEN
    CREATE TRIGGER trg_features_updated_at
      BEFORE UPDATE ON transaction_features
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

COMMIT;
