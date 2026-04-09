# Ledgerly — AI Database Schema

PostgreSQL schema for Phase 1 AI features: transaction categorization, ML feature store, and model output storage.

## Migrations (run in order)

| File | Description |
|------|-------------|
| `migrations/001_base_transactions.sql` | Base `accounts` + `transactions` tables (Plaid data model) |
| `migrations/002_category_taxonomy.sql` | Hierarchical `transaction_categories` + `transaction_category_labels` |
| `migrations/003_feature_store.sql` | ML feature vectors per transaction (`transaction_features`) |
| `migrations/004_ai_predictions.sql` | Model predictions, anomaly scores, correction feedback (`ai_predictions`) |

## Seeds

| File | Description |
|------|-------------|
| `seeds/001_categories.sql` | 13 root + 60+ primary category taxonomy, idempotent (`ON CONFLICT DO NOTHING`) |

## Running

```bash
# Apply all migrations
for f in db/migrations/*.sql; do psql $DATABASE_URL -f "$f"; done

# Seed categories
psql $DATABASE_URL -f db/seeds/001_categories.sql
```

## Table Overview

```
accounts                  ← Plaid-linked bank accounts
transactions              ← Transaction ledger (sourced from Plaid transactionsSync)
transaction_categories    ← Hierarchical category taxonomy (3 levels)
transaction_category_labels ← Transaction ↔ category mapping (multi-source)
transaction_features      ← ML feature vectors (Phase 1+2 training data)
ai_predictions            ← Model outputs: categorization, anomaly, forecast
```

## Extensibility Notes

- `transaction_features.name_embedding` (JSONB) is reserved for Phase 3 sentence embeddings. Swap to `pgvector` extension when upgrading.
- `ai_predictions.output` (JSONB) catches any future model outputs not covered by typed columns.
- Feature version column (`feature_version`) allows schema evolution without reprocessing.
