-- Migration: 004_ai_predictions
-- Description: Model predictions, confidence scores, and anomaly flags.
--              Stores outputs for all AI model types (categorization, anomaly, forecast).
--              Tracks user corrections for future fine-tuning / feedback loop.

BEGIN;

CREATE TABLE IF NOT EXISTS ai_predictions (
  id                      SERIAL  PRIMARY KEY,
  transaction_id          VARCHAR(255) NOT NULL
                            REFERENCES transactions(transaction_id) ON DELETE CASCADE,

  -- ── Model identity ──────────────────────────────────────────────
  model_name              VARCHAR(100) NOT NULL,   -- e.g. 'category_classifier', 'anomaly_detector'
  model_version           VARCHAR(50)  NOT NULL,   -- semver or date-stamp
  prediction_type         VARCHAR(50)  NOT NULL     -- 'categorization' | 'anomaly' | 'forecast'
                            CHECK (prediction_type IN ('categorization', 'anomaly', 'forecast')),

  -- ── Categorization output ───────────────────────────────────────
  predicted_category_id   INTEGER
                            REFERENCES transaction_categories(id) ON DELETE SET NULL,
  category_confidence     DECIMAL(5,4)             -- 0.0000–1.0000
                            CHECK (category_confidence IS NULL
                              OR (category_confidence >= 0 AND category_confidence <= 1)),
  -- Top-N alternatives: [{category_id: int, slug: str, confidence: float}]
  top_categories          JSONB,

  -- ── Anomaly detection output ────────────────────────────────────
  is_anomaly              BOOLEAN,
  anomaly_score           DECIMAL(5,4)             -- 0=normal, 1=max anomaly
                            CHECK (anomaly_score IS NULL
                              OR (anomaly_score >= 0 AND anomaly_score <= 1)),
  anomaly_reason          TEXT,                    -- human-readable explanation
  -- Anomaly sub-types: 'amount_spike', 'unusual_merchant', 'off_schedule', 'duplicate'
  anomaly_type            VARCHAR(50),

  -- ── Forecast output (Phase 3) ───────────────────────────────────
  -- Stores point-estimate + interval for future spend predictions
  forecast_amount         DECIMAL(14,2),
  forecast_date           DATE,
  forecast_interval_low   DECIMAL(14,2),
  forecast_interval_high  DECIMAL(14,2),

  -- ── General extensible output ───────────────────────────────────
  output                  JSONB,                   -- full model output blob for future models

  -- ── User feedback / correction loop ────────────────────────────
  was_corrected           BOOLEAN NOT NULL DEFAULT FALSE,
  correction_category_id  INTEGER
                            REFERENCES transaction_categories(id) ON DELETE SET NULL,
  corrected_at            TIMESTAMP,
  correction_source       VARCHAR(20),             -- 'user' | 'rule'

  predicted_at            TIMESTAMP DEFAULT NOW(),
  created_at              TIMESTAMP DEFAULT NOW(),
  updated_at              TIMESTAMP DEFAULT NOW()
);

-- One active prediction per model+type per transaction
CREATE UNIQUE INDEX IF NOT EXISTS idx_predictions_tx_model
  ON ai_predictions(transaction_id, model_name, prediction_type);

CREATE INDEX IF NOT EXISTS idx_predictions_transaction
  ON ai_predictions(transaction_id);

CREATE INDEX IF NOT EXISTS idx_predictions_anomaly
  ON ai_predictions(is_anomaly, anomaly_score DESC)
  WHERE is_anomaly = TRUE;

CREATE INDEX IF NOT EXISTS idx_predictions_corrected
  ON ai_predictions(was_corrected) WHERE was_corrected = TRUE;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_predictions_updated_at'
  ) THEN
    CREATE TRIGGER trg_predictions_updated_at
      BEFORE UPDATE ON ai_predictions
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

COMMIT;
