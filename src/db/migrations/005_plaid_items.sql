-- Migration: 005_plaid_items
-- Description: Server-side storage for Plaid linked items and access tokens.
--              Access tokens are stored here so users never need their own Plaid account.
--              The Ledgerly backend holds the Plaid credentials and proxies all calls.

BEGIN;

CREATE TABLE IF NOT EXISTS plaid_items (
  id              SERIAL PRIMARY KEY,
  item_id         VARCHAR(255) UNIQUE NOT NULL,   -- Plaid item_id
  user_id         VARCHAR(255) NOT NULL,           -- App user identifier
  access_token    TEXT         NOT NULL,           -- Plaid access token (sensitive)
  institution_id  VARCHAR(255),
  institution_name VARCHAR(255),
  cursor          TEXT,                            -- transactionsSync pagination cursor
  status          VARCHAR(50)  DEFAULT 'active',  -- active | item_login_required | error
  created_at      TIMESTAMP    DEFAULT NOW(),
  updated_at      TIMESTAMP    DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_plaid_items_user_id ON plaid_items(user_id);

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_plaid_items_updated_at'
  ) THEN
    CREATE TRIGGER trg_plaid_items_updated_at
      BEFORE UPDATE ON plaid_items
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

COMMIT;
