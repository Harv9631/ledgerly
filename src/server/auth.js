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

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) return res.status(401).json({ error: 'Invalid token' });

  req.user = { id: user.id, email: user.email };
  next();
}

module.exports = { requireAuth, supabase };
