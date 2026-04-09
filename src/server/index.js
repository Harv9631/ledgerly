'use strict';

// Load own .env first, then fall back to parent src/.env
require('dotenv').config();
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env'), override: false });

// When spawned by Electron, Plaid credentials arrive as env vars.
// Persist them to .env so standalone web server runs also have them.
(function persistCredentials() {
  const fs = require('fs'), path = require('path');
  const envFile = path.join(__dirname, '.env');
  const id  = process.env.PLAID_CLIENT_ID;
  const sec = process.env.PLAID_SECRET;
  const env = process.env.PLAID_ENV;
  if (!id || !sec) return; // nothing to persist
  try {
    let content = '';
    try { content = fs.readFileSync(envFile, 'utf8'); } catch {}
    const set = (text, key, val) => {
      const re = new RegExp('^' + key + '=.*$', 'm');
      return re.test(text) ? text.replace(re, key + '=' + val) : text + '\n' + key + '=' + val;
    };
    content = set(content, 'PLAID_CLIENT_ID', id);
    content = set(content, 'PLAID_SECRET', sec);
    if (env) content = set(content, 'PLAID_ENV', env);
    fs.writeFileSync(envFile, content.trimStart());
  } catch {}
})();

const express = require('express');
const cors = require('cors');
const path = require('path');
const plaidRoutes = require('./routes/plaid');
const { requireAuth } = require('./auth');

const app = express();
const PORT = process.env.PORT || 3210;

// Middleware
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  allowedHeaders: ['Content-Type', 'Authorization', 'X-User-Id']
}));
app.use(express.json());

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', env: process.env.PLAID_ENV || 'sandbox' });
});

// Serve login.html with Supabase config injected so keys stay in env vars
app.get('/login', (_req, res) => {
  const fs   = require('fs');
  const html = fs.readFileSync(path.join(__dirname, '..', 'login.html'), 'utf8');
  const config = `<script>
    window.__SUPABASE_URL__      = ${JSON.stringify(process.env.SUPABASE_URL || '')};
    window.__SUPABASE_ANON_KEY__ = ${JSON.stringify(process.env.SUPABASE_ANON_KEY || '')};
  </script>`;
  res.send(html.replace('</head>', config + '</head>'));
});

// Serve Supabase SDK locally so login page doesn't depend on CDN
app.get('/supabase.js', (_req, res) => {
  res.setHeader('Content-Type', 'application/javascript');
  res.sendFile(path.join(__dirname, 'node_modules/@supabase/supabase-js/dist/umd/supabase.js'));
});

// Serve frontend static files (enables plaid-link.html from HTTP origin)
app.use(express.static(path.join(__dirname, '..')));

// Serve cached Plaid Link SDK downloaded by the Electron main process via electron.net
// (Chromium network stack bypasses the Cloudflare bot-protection that blocks Node.js TLS)
app.get('/plaid-sdk.js', (_req, res) => {
  const fs = require('fs');
  const cacheDir = process.env.PLAID_SDK_CACHE_DIR;
  if (cacheDir) {
    const cachePath = require('path').join(cacheDir, 'plaid-sdk.js');
    if (fs.existsSync(cachePath)) {
      res.setHeader('Content-Type', 'application/javascript');
      res.setHeader('Cache-Control', 'public, max-age=3600');
      return res.sendFile(cachePath);
    }
  }
  // Cache not ready yet — return a stub so the page can fall back to CDN
  res.status(503).send('// Plaid SDK not yet cached. Retry or use CDN fallback.');
});

// Plaid proxy routes — protected by auth
app.use('/api/plaid', requireAuth, plaidRoutes);

// Error handler
app.use((err, _req, res, _next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => {
  console.log(`Ledgerly server running on port ${PORT} (Plaid env: ${process.env.PLAID_ENV || 'sandbox'})`);
});
