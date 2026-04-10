'use strict';

/**
 * Ledgerly database — JSON file with Supabase Storage backup.
 *
 * Priority:
 *   1. Local file (fast, used as write-through cache)
 *   2. Supabase Storage (survives Railway redeploys)
 *
 * On startup: loads from Supabase if local file missing.
 * On write:   writes locally AND pushes to Supabase (async, non-blocking).
 */

const fs   = require('fs');
const path = require('path');

const dbDir  = process.env.DB_PATH || __dirname;
const dbFile = path.join(dbDir, 'ledgerly-data.json');
const BUCKET = 'ledgerly';
const OBJECT = 'db.json';

try { fs.mkdirSync(dbDir, { recursive: true }); } catch {}

// Supabase Storage client (needs service role key to bypass RLS)
let sbStorage = null;
const sbUrl = process.env.SUPABASE_URL;
const sbKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (sbUrl && sbKey) {
  try {
    const { createClient } = require('@supabase/supabase-js');
    sbStorage = createClient(sbUrl, sbKey).storage;
  } catch {}
}

// ── Load / Save ──────────────────────────────────────────────────────────────

function loadLocal() {
  try { return JSON.parse(fs.readFileSync(dbFile, 'utf8')); }
  catch { return null; }
}

async function loadFromSupabase() {
  if (!sbStorage) { console.log('[DB] No Supabase storage client'); return null; }
  try {
    const { data, error } = await sbStorage.from(BUCKET).download(OBJECT);
    if (error) { console.log('[DB] Supabase download error:', error.message || JSON.stringify(error)); return null; }
    if (!data) { console.log('[DB] Supabase returned no data'); return null; }
    const text = await data.text();
    return JSON.parse(text);
  } catch(e) { console.log('[DB] Supabase load exception:', e.message); return null; }
}

function load() {
  return loadLocal() || { plaid_items: [], user_states: {} };
}

function save(data) {
  const json = JSON.stringify(data, null, 2);
  try { fs.writeFileSync(dbFile, json); } catch {}
  // Push to Supabase Storage asynchronously
  if (sbStorage) {
    const buf = Buffer.from(json, 'utf8');
    sbStorage.from(BUCKET).upload(OBJECT, buf, { contentType: 'application/json', upsert: true })
      .then(r => { if (r.error) console.log('[DB] Supabase upload error:', r.error.message || JSON.stringify(r.error)); })
      .catch(e => console.log('[DB] Supabase upload exception:', e.message));
  }
}

// On server start: restore from Supabase if local file is missing
(async function restoreFromSupabase() {
  if (loadLocal()) { console.log('[DB] Local file found, no restore needed'); return; }
  console.log('[DB] No local file, attempting Supabase restore...');
  const remote = await loadFromSupabase();
  if (remote) {
    try { fs.writeFileSync(dbFile, JSON.stringify(remote, null, 2)); } catch {}
    console.log('[DB] Restored data from Supabase Storage');
  } else {
    console.log('[DB] No Supabase data found, starting fresh');
  }
})();

// ── Query interface (mimics pg pool.query) ───────────────────────────────────

function query(sql, params = []) {
  const s = sql.replace(/\s+/g, ' ').trim();

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

  if (/INSERT INTO plaid_items/.test(s)) {
    const [item_id, user_id, access_token, institution_id, institution_name] = params;
    const data = load();
    data.plaid_items = data.plaid_items || [];
    const existing = data.plaid_items.find(r => r.item_id === item_id);
    const now = new Date().toISOString();
    if (existing) {
      existing.access_token = access_token;
      existing.status       = 'active';
      existing.updated_at   = now;
    } else {
      data.plaid_items.push({ item_id, user_id, access_token, institution_id, institution_name,
        cursor: null, status: 'active', created_at: now, updated_at: now });
    }
    save(data);
    return Promise.resolve({ rows: [], rowCount: 1 });
  }

  if (/UPDATE plaid_items SET cursor/.test(s)) {
    const [cursor, item_id] = params;
    const data = load();
    const item = (data.plaid_items || []).find(r => r.item_id === item_id);
    if (item) { item.cursor = cursor; item.updated_at = new Date().toISOString(); }
    save(data);
    return Promise.resolve({ rows: [], rowCount: item ? 1 : 0 });
  }

  if (/UPDATE plaid_items SET status/.test(s)) {
    const status = params[0], item_id = params[1];
    const data = load();
    const item = (data.plaid_items || []).find(r => r.item_id === item_id);
    if (item) { item.status = status; item.updated_at = new Date().toISOString(); }
    save(data);
    return Promise.resolve({ rows: [], rowCount: item ? 1 : 0 });
  }

  if (/UPDATE plaid_items SET updated_at/.test(s)) {
    const item_id = params[0];
    const data = load();
    const item = (data.plaid_items || []).find(r => r.item_id === item_id);
    if (item) item.updated_at = new Date().toISOString();
    save(data);
    return Promise.resolve({ rows: [], rowCount: item ? 1 : 0 });
  }

  if (/DELETE FROM plaid_items/.test(s)) {
    const item_id = params[0];
    const data = load();
    const before = (data.plaid_items || []).length;
    data.plaid_items = (data.plaid_items || []).filter(r => r.item_id !== item_id);
    save(data);
    return Promise.resolve({ rows: [], rowCount: before - data.plaid_items.length });
  }

  return Promise.resolve({ rows: [], rowCount: 0 });
}

// ── User state ───────────────────────────────────────────────────────────────

function getUserState(userId) {
  try { return (load().user_states || {})[userId] || null; } catch { return null; }
}

function saveUserState(userId, appState) {
  try {
    const data = load();
    data.user_states = data.user_states || {};
    data.user_states[userId] = appState;
    save(data);
  } catch {}
}

module.exports = { query, getUserState, saveUserState };
