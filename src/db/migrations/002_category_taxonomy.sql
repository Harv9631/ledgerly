-- Migration: 002_category_taxonomy
-- Description: Hierarchical transaction category tree.
--              Supports 3 levels: root → primary → subcategory.
--              Seed data in seeds/001_categories.sql.

BEGIN;

-- ---------------------------------------------------------------
-- Category taxonomy (hierarchical, self-referencing)
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transaction_categories (
  id             SERIAL  PRIMARY KEY,
  slug           VARCHAR(100) NOT NULL UNIQUE,     -- machine-readable key (e.g. 'food_restaurants')
  name           VARCHAR(100) NOT NULL,             -- display name
  parent_id      INTEGER REFERENCES transaction_categories(id) ON DELETE CASCADE,
  level          SMALLINT NOT NULL DEFAULT 0        -- 0=root, 1=primary, 2=subcategory
                   CHECK (level BETWEEN 0 AND 2),
  icon           VARCHAR(50),                       -- emoji or icon name for UI
  color          VARCHAR(7),                        -- hex color (e.g. '#4CAF50')
  description    TEXT,
  is_income      BOOLEAN NOT NULL DEFAULT FALSE,    -- income vs expense classification
  is_transfer    BOOLEAN NOT NULL DEFAULT FALSE,    -- transfer between own accounts
  is_system      BOOLEAN NOT NULL DEFAULT TRUE,     -- system-defined vs user-created
  sort_order     SMALLINT NOT NULL DEFAULT 0,
  created_at     TIMESTAMP DEFAULT NOW(),
  updated_at     TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_categories_parent
  ON transaction_categories(parent_id);

CREATE INDEX IF NOT EXISTS idx_categories_level
  ON transaction_categories(level);

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_categories_updated_at'
  ) THEN
    CREATE TRIGGER trg_categories_updated_at
      BEFORE UPDATE ON transaction_categories
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- ---------------------------------------------------------------
-- Transaction ↔ Category labels
-- Supports multiple labels per transaction (AI, user, Plaid, rule)
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transaction_category_labels (
  id             SERIAL  PRIMARY KEY,
  transaction_id VARCHAR(255) NOT NULL
                   REFERENCES transactions(transaction_id) ON DELETE CASCADE,
  category_id    INTEGER NOT NULL
                   REFERENCES transaction_categories(id) ON DELETE RESTRICT,

  -- Label provenance
  source         VARCHAR(20) NOT NULL               -- 'ai' | 'user' | 'plaid' | 'rule'
                   CHECK (source IN ('ai', 'user', 'plaid', 'rule')),
  confidence     DECIMAL(5,4)                       -- 0.0000–1.0000, NULL for user/rule labels
                   CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
  model_name     VARCHAR(100),                      -- which model produced this label
  model_version  VARCHAR(50),

  -- User review state
  is_confirmed   BOOLEAN NOT NULL DEFAULT FALSE,    -- user explicitly confirmed
  is_rejected    BOOLEAN NOT NULL DEFAULT FALSE,    -- user explicitly rejected

  labeled_at     TIMESTAMP DEFAULT NOW(),
  confirmed_at   TIMESTAMP,
  created_at     TIMESTAMP DEFAULT NOW(),
  updated_at     TIMESTAMP DEFAULT NOW()
);

-- Only one active label per source per transaction (latest wins within source)
CREATE UNIQUE INDEX IF NOT EXISTS idx_labels_tx_source
  ON transaction_category_labels(transaction_id, source)
  WHERE is_rejected = FALSE;

CREATE INDEX IF NOT EXISTS idx_labels_transaction
  ON transaction_category_labels(transaction_id);

CREATE INDEX IF NOT EXISTS idx_labels_category
  ON transaction_category_labels(category_id);

COMMIT;
