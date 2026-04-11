'use strict';

/**
 * Supabase auth middleware.
 * Validates the JWT Bearer token sent by the browser and attaches
 * req.user = { id, email } so route handlers know who is calling.
 *
 * The SUPABASE_URL and SUPABASE_ANON_KEY env vars are set at deploy time.
 * In development (Electron), auth is bypassed and req.user = { id: 'local' }.
 */

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL      = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

// Use service role key for auth verification — bypasses RLS and works with all token formats
const supabaseAdmin = SUPABASE_URL && SUPABASE_SERVICE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, { auth: { autoRefreshToken: false, persistSession: false } })
  : null;

const supabase = SUPABASE_URL && SUPABASE_ANON_KEY
  ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  : null;

// Cache token → user mapping for 5 minutes to avoid repeated Supabase API calls
const _tokenCache = new Map();
const TOKEN_CACHE_TTL = 5 * 60 * 1000;
const TOKEN_CACHE_MAX = 500;

// Prune expired entries every 10 minutes
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of _tokenCache) {
    if (now - v.ts >= TOKEN_CACHE_TTL) _tokenCache.delete(k);
  }
}, 10 * 60 * 1000);

async function requireAuth(req, res, next) {
  // Desktop / Electron mode — no auth required
  if (!supabase && !supabaseAdmin) {
    req.user = { id: req.headers['x-user-id'] || 'local', email: null };
    return next();
  }

  const header = req.headers['authorization'] || '';
  const token  = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) return res.status(401).json({ error: 'Unauthorized' });

  // Check cache first — avoids Supabase API call on every request
  const cached = _tokenCache.get(token);
  if (cached && Date.now() - cached.ts < TOKEN_CACHE_TTL) {
    req.user = cached.user;
    return next();
  }

  let resolvedUser = null;

  // Always verify token with Supabase (signature-checked, not just decoded)
  const client = supabaseAdmin || supabase;
  try {
    const { data: { user }, error } = await client.auth.getUser(token);
    if (!error && user && user.id) resolvedUser = { id: user.id, email: user.email };
  } catch {}

  if (!resolvedUser) return res.status(401).json({ error: 'Invalid token' });

  // Cache the result (evict oldest if at capacity)
  if (_tokenCache.size >= TOKEN_CACHE_MAX) {
    const oldest = _tokenCache.keys().next().value;
    _tokenCache.delete(oldest);
  }
  _tokenCache.set(token, { user: resolvedUser, ts: Date.now() });
  req.user = resolvedUser;
  next();
}

module.exports = { requireAuth, supabase };
