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

// AI Chat — Server-Sent Events streaming endpoint
// POST /api/ai/chat  { message, history: [{role,content}], financialContext }
app.post('/api/ai/chat', requireAuth, async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return res.status(503).json({ error: 'No Anthropic API key configured. Add ANTHROPIC_API_KEY to environment variables.' });
  }

  const { message, history = [], financialContext } = req.body;
  if (!message) return res.status(400).json({ error: 'message required' });

  const systemPrompt = `You are a personal financial advisor assistant inside Ledgerly, an income and debt tracking app. Help users understand their financial situation and provide actionable, data-driven advice.

CONSTRAINTS:
- Only answer questions related to personal finance, budgeting, debt management, savings, income, and financial planning.
- Do NOT advise on specific stock picks, securities trading, tax filing, or legal matters.
- Do NOT engage with topics unrelated to personal finance. Politely redirect if asked.
- Use the financial snapshot below to give personalized answers. Never reveal raw account numbers or identifiers.
- Be concise, encouraging, and practical.

USER FINANCIAL SNAPSHOT:
${financialContext || 'No financial data available yet.'}`;

  const messages = [
    ...history.slice(-40).map(h => ({ role: h.role, content: h.content })),
    { role: 'user', content: message }
  ];

  // Set up SSE
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  const send = (type, data) => res.write(`data: ${JSON.stringify({ type, ...data })}\n\n`);

  try {
    const { default: Anthropic } = require('@anthropic-ai/sdk');
    const client = new Anthropic({ apiKey });
    const stream = client.messages.stream({ model: 'claude-sonnet-4-6', max_tokens: 1024, system: systemPrompt, messages });
    stream.on('text', (text) => send('chunk', { text }));
    const final = await stream.finalMessage();
    send('done', { usage: final.usage });
  } catch (err) {
    send('error', { error: err.message || 'AI error' });
  }
  res.end();
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
