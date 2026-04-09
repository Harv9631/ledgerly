'use strict';

/**
 * Lightweight JSON-file database for Ledgerly desktop.
 * Replaces PostgreSQL — no external server or native modules required.
 * Stores Plaid items (access tokens, cursors) in a JSON file in userData.
 *
 * Exposes query(sql, params) mimicking pg's pool.query() so routes are unchanged.
 * Handles the specific queries used in plaid.js; unrecognised queries are no-ops.
 */

const fs   = require('fs');
const path = require('path');

const dbDir  = process.env.DB_PATH || __dirname;
const dbFile = path.join(dbDir, 'ledgerly-data.json');

function load() {
  try { return JSON.parse(fs.readFileSync(dbFile, 'utf8')); }
  catch { return { plaid_items: [] }; }
}

function save(data) {
  fs.writeFileSync(dbFile, JSON.stringify(data, null, 2));
}

function query(sql, params = []) {
  const s = sql.replace(/\s+/g, ' ').trim();
  const upper = s.toUpperCase();

  // ── SELECT plaid_items ──────────────────────────────────────────────────────
  if (/SELECT .* FROM plaid_items WHERE user_id/.test(s)) {
    const userId = params[0];
    const data = load();
    const rows = (data.plaid_items || [])
      .filter(r => r.user_id === userId)
      .sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
    return Promise.resolve({ rows, rowCount: rows.length });
  }

  if (/SELECT .* FROM plaid_items WHERE item_id/.test(s)) {
    const itemId = params[0], userId = params[1];
    const data = load();
    const rows = (data.plaid_items || []).filter(r => r.item_id === itemId && r.user_id === userId);
    return Promise.resolve({ rows, rowCount: rows.length });
  }

  // ── INSERT plaid_items ──────────────────────────────────────────────────────
  if (/INSERT INTO plaid_items/.test(s)) {
    const [item_id, user_id, access_token, institution_id, institution_name] = params;
    const data = load();
    data.plaid_items = data.plaid_items || [];
    const existing = data.plaid_items.find(r => r.item_id === item_id);
    const now = new Date().toISOString();
    if (existing) {
      existing.access_token     = access_token;
      existing.status           = 'active';
      existing.updated_at       = now;
    } else {
      data.plaid_items.push({ item_id, user_id, access_token, institution_id, institution_name,
        cursor: null, status: 'active', created_at: now, updated_at: now });
    }
    save(data);
    return Promise.resolve({ rows: [], rowCount: 1 });
  }

  // ── UPDATE cursor ───────────────────────────────────────────────────────────
  if (/UPDATE plaid_items SET cursor/.test(s)) {
    const [cursor, item_id] = params;
    const data = load();
    const item = (data.plaid_items || []).find(r => r.item_id === item_id);
    if (item) { item.cursor = cursor; item.updated_at = new Date().toISOString(); }
    save(data);
    return Promise.resolve({ rows: [], rowCount: item ? 1 : 0 });
  }

  // ── UPDATE status ───────────────────────────────────────────────────────────
  if (/UPDATE plaid_items SET status/.test(s)) {
    const status = params[0], item_id = params[1];
    const data = load();
    const item = (data.plaid_items || []).find(r => r.item_id === item_id);
    if (item) { item.status = status; item.updated_at = new Date().toISOString(); }
    save(data);
    return Promise.resolve({ rows: [], rowCount: item ? 1 : 0 });
  }

  // ── UPDATE updated_at (webhook) ─────────────────────────────────────────────
  if (/UPDATE plaid_items SET updated_at/.test(s)) {
    const item_id = params[0];
    const data = load();
    const item = (data.plaid_items || []).find(r => r.item_id === item_id);
    if (item) item.updated_at = new Date().toISOString();
    save(data);
    return Promise.resolve({ rows: [], rowCount: item ? 1 : 0 });
  }

  // ── DELETE plaid_items ──────────────────────────────────────────────────────
  if (/DELETE FROM plaid_items/.test(s)) {
    const item_id = params[0];
    const data = load();
    const before = (data.plaid_items || []).length;
    data.plaid_items = (data.plaid_items || []).filter(r => r.item_id !== item_id);
    save(data);
    return Promise.resolve({ rows: [], rowCount: before - data.plaid_items.length });
  }

  // ── accounts / transactions (best-effort server-side cache — no-op) ─────────
  return Promise.resolve({ rows: [], rowCount: 0 });
}

module.exports = { query };
