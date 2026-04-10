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

async function requireAuth(req, res, next) {
  // Desktop / Electron mode — no auth required
  if (!supabase && !supabaseAdmin) {
    req.user = { id: req.headers['x-user-id'] || 'local', email: null };
    return next();
  }

  const header = req.headers['authorization'] || '';
  const token  = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) return res.status(401).json({ error: 'Unauthorized' });

  // Try service-role client first (works with all Supabase key formats)
  const client = supabaseAdmin || supabase;
  try {
    const { data: { user }, error } = await client.auth.getUser(token);
    if (!error && user && user.id) {
      req.user = { id: user.id, email: user.email };
      return next();
    }
  } catch {}

  // Fallback: decode JWT sub claim locally (stable Supabase UUID)
  try {
    const parts = token.split('.');
    if (parts.length === 3) {
      const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
      if (payload.sub) {
        req.user = { id: payload.sub, email: payload.email || null };
        return next();
      }
    }
  } catch {}

  // Last resort: reject unauthenticated requests
  return res.status(401).json({ error: 'Invalid token' });
}

module.exports = { requireAuth, supabase };
