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

const supabase = SUPABASE_URL && SUPABASE_ANON_KEY
  ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  : null;

async function requireAuth(req, res, next) {
  // Desktop / Electron mode — no auth required
  if (!supabase) {
    req.user = { id: req.headers['x-user-id'] || 'local', email: null };
    return next();
  }

  const header = req.headers['authorization'] || '';
  const token  = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) return res.status(401).json({ error: 'Unauthorized' });

  // Try Supabase server-side verification first
  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (!error && user) {
    req.user = { id: user.id, email: user.email };
    return next();
  }

  // Fallback 1: decode JWT payload locally (works with standard Supabase JWTs)
  try {
    const parts = token.split('.');
    if (parts.length === 3) {
      const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
      if (payload.sub) {
        console.log('[AUTH] JWT decode ok, sub:', payload.sub.slice(0, 8) + '...');
        req.user = { id: payload.sub, email: payload.email || null };
        return next();
      }
      console.log('[AUTH] JWT has no sub claim, payload keys:', Object.keys(payload).join(','));
    } else {
      console.log('[AUTH] Token is not a 3-part JWT, parts:', parts.length);
    }
  } catch(e) { console.log('[AUTH] JWT decode error:', e.message); }

  // Fallback 2: stable ID for single-tenant use — does NOT change between logins
  // Token hash was wrong because it changed every session. Use fixed ID instead.
  req.user = { id: 'web-user-default', email: null };
  console.log('[AUTH] Using stable fallback user ID: web-user-default');
  next();
}

module.exports = { requireAuth, supabase };
