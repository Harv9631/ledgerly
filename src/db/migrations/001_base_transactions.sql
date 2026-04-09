-- Migration: 001_base_transactions
-- Description: Base transactions table mirroring Plaid transaction structure.
--              Foundation for all AI feature extraction and model pipelines.
-- Backward-compatible: no changes to existing JSON file storage, this is additive.

BEGIN;

-- Plaid-linked bank accounts
CREATE TABLE IF NOT EXISTS accounts (
  id                SERIAL PRIMARY KEY,
  account_id        VARCHAR(255) UNIQUE NOT NULL,  -- Plaid account_id
  item_id           VARCHAR(255) NOT NULL,           -- Plaid item_id
  name              VARCHAR(255) NOT NULL,
  official_name     VARCHAR(255),
  type              VARCHAR(50)  NOT NULL,            -- depository, credit, loan, investment
  subtype           VARCHAR(50),                      -- checking, savings, credit card, etc.
  currency_code     VARCHAR(10)  DEFAULT 'USD',
  current_balance   DECIMAL(14,2),
  available_balance DECIMAL(14,2),
  limit_amount      DECIMAL(14,2),
  last_synced_at    TIMESTAMP,
  created_at        TIMESTAMP    DEFAULT NOW(),
  updated_at        TIMESTAMP    DEFAULT NOW()
);

-- Core transaction ledger (sourced from Plaid transactionsSync)
CREATE TABLE IF NOT EXISTS transactions (
  id                          SERIAL PRIMARY KEY,
  transaction_id              VARCHAR(255) UNIQUE NOT NULL,   -- Plaid transaction_id
  account_id                  VARCHAR(255) NOT NULL
                                REFERENCES accounts(account_id) ON DELETE CASCADE,

  -- Core financial fields
  amount                      DECIMAL(14,2)  NOT NULL,        -- Positive = debit, negative = credit
  iso_currency_code           VARCHAR(10)    DEFAULT 'USD',
  date                        DATE           NOT NULL,
  authorized_date             DATE,

  -- Merchant / description
  name                        VARCHAR(500)   NOT NULL,         -- Raw transaction description
  merchant_name               VARCHAR(500),
  merchant_id                 VARCHAR(255),                    -- Plaid merchant_id if available

  -- Channel & type
  payment_channel             VARCHAR(50),                     -- online | in store | other
  transaction_type            VARCHAR(50),                     -- place | digital | special | unresolved

  -- Status
  pending                     BOOLEAN        DEFAULT FALSE,
  pending_transaction_id      VARCHAR(255),                    -- links pending → posted

  -- Plaid category hints (kept for backward-compat & feature extraction)
  plaid_category              JSONB,                           -- ["Food and Drink", "Restaurants"]
  plaid_category_id           VARCHAR(50),
  personal_finance_category   VARCHAR(100),                    -- primary (e.g. FOOD_AND_DRINK)
  personal_finance_detail     VARCHAR(100),                    -- detailed (e.g. FOOD_AND_DRINK_FAST_FOOD)
  pfc_confidence              VARCHAR(20),                     -- VERY_HIGH | HIGH | MEDIUM | LOW | UNKNOWN

  -- Location
  location                    JSONB,                           -- {address, city, state, zip, lat, lon, country}

  -- Full raw payload for audit / reprocessing
  raw_plaid_data              JSONB,

  synced_at                   TIMESTAMP      DEFAULT NOW(),
  created_at                  TIMESTAMP      DEFAULT NOW(),
  updated_at                  TIMESTAMP      DEFAULT NOW()
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_transactions_account_date
  ON transactions(account_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_transactions_date
  ON transactions(date DESC);

CREATE INDEX IF NOT EXISTS idx_transactions_merchant
  ON transactions(merchant_name);

CREATE INDEX IF NOT EXISTS idx_transactions_pending
  ON transactions(pending) WHERE pending = TRUE;

-- Trigger: auto-update updated_at on any row change
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_transactions_updated_at'
  ) THEN
    CREATE TRIGGER trg_transactions_updated_at
      BEFORE UPDATE ON transactions
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_accounts_updated_at'
  ) THEN
    CREATE TRIGGER trg_accounts_updated_at
      BEFORE UPDATE ON accounts
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

COMMIT;
