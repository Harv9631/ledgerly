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
const plaidRoutes  = require('./routes/plaid');
const stripeRoutes = require('./routes/stripe');
const { requireAuth } = require('./auth');

const app = express();

// Per-user rate limiting for AI endpoints (50 requests/day per user)
const _aiRateLimits = new Map();
function checkAiRateLimit(userId) {
  const today = new Date().toISOString().slice(0, 10);
  const key = userId + ':' + today;
  const count = _aiRateLimits.get(key) || 0;
  if (count >= 50) return false;
  _aiRateLimits.set(key, count + 1);
  // Clean up old entries daily
  for (const k of _aiRateLimits.keys()) {
    if (!k.endsWith(today)) _aiRateLimits.delete(k);
  }
  return true;
}
function getAiRateCount(userId) {
  const today = new Date().toISOString().slice(0, 10);
  return _aiRateLimits.get(userId + ':' + today) || 0;
}
const PORT = process.env.PORT || 3210;

// Middleware
// CORS_ORIGIN can be a single origin or comma-separated list (e.g. "http://localhost:3210,https://ledgerly.app")
app.use(cors({
  origin: function(origin, callback) {
    // Allow requests with no origin (Electron, curl, server-to-server)
    if (!origin) return callback(null, true);
    const allowed = (process.env.CORS_ORIGIN || 'http://localhost:3210')
      .split(',').map(s => s.trim());
    if (allowed.includes(origin)) return callback(null, true);
    callback(new Error('Not allowed by CORS'));
  },
  allowedHeaders: ['Content-Type', 'Authorization', 'X-User-Id']
}));
// Stripe webhook needs raw body for signature verification — mount BEFORE json parser
app.use('/api/stripe/webhook', express.raw({ type: 'application/json' }), stripeRoutes);
app.use(express.json({ limit: '5mb' }));

// Health check
app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    env: process.env.PLAID_ENV || 'sandbox',
    hasAiKey: !!process.env.ANTHROPIC_API_KEY,
    hasPlaidId: !!process.env.PLAID_CLIENT_ID,
    hasSupabase: !!process.env.SUPABASE_URL
  });
});

// AI Chat — simple JSON endpoint (SSE buffered by Railway proxy, so use plain request/response)
// POST /api/ai/chat  { message, history: [{role,content}], financialContext }
app.post('/api/ai/chat', requireAuth, async (req, res) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return res.status(503).json({ error: 'No Anthropic API key configured. Add ANTHROPIC_API_KEY to environment variables.' });
  }

  const { message, history = [], financialContext } = req.body;
  if (!message) return res.status(400).json({ error: 'message required' });
  if (typeof message === 'string' && message.length > 5000) return res.status(400).json({ error: 'Message too long (max 5000 characters)' });

  if (!checkAiRateLimit(req.user.id)) {
    return res.status(429).json({ error: 'Daily limit reached (50 messages/day). Try again tomorrow.' });
  }

  const systemPrompt = `You are a personal financial advisor assistant inside Ledgerly, an income and debt tracking app. Help users understand their financial situation and provide actionable, data-driven advice.

CONSTRAINTS:
- Only answer questions related to personal finance, budgeting, debt management, savings, income, and financial planning.
- Do NOT advise on specific stock picks, securities trading, tax filing, or legal matters.
- Do NOT engage with topics unrelated to personal finance. Politely redirect if asked.
- Use the financial snapshot below to give personalized answers. Never reveal raw account numbers or identifiers.
- Be concise, encouraging, and practical.

ACTION COMMANDS:
When the user asks you to create, add, or set up something in the app (budget, income, expense, debt, goal, savings bucket, subscription), include a JSON action block at the END of your response. Write your friendly response first, then on a new line add the action block wrapped in \`\`\`action tags.

Supported actions:
- create_budget: { "action": "create_budget", "category": "<category>", "limit": <number> }
- add_income: { "action": "add_income", "name": "<name>", "amount": <number>, "frequency": "monthly|weekly|biweekly|annually", "category": "<category>" }
- add_expense: { "action": "add_expense", "name": "<name>", "amount": <number>, "frequency": "monthly|weekly|biweekly|annually", "category": "<category>" }
- add_debt: { "action": "add_debt", "name": "<name>", "balance": <number>, "rate": <number>, "payment": <number>, "type": "credit-card|student-loan|mortgage|auto-loan|personal-loan|medical|other" }
- add_goal: { "action": "add_goal", "name": "<name>", "target": <number>, "current": <number>, "monthly": <number> }
- add_savings: { "action": "add_savings", "name": "<name>", "target": <number>, "balance": <number> }
- add_subscription: { "action": "add_subscription", "name": "<name>", "amount": <number>, "cycle": "monthly|yearly|weekly" }
- navigate: { "action": "navigate", "page": "<page_name>" }

Example response when user says "Set a $500 grocery budget":
Great! I'll set up a $500 monthly budget for Groceries.

\`\`\`action
{"action": "create_budget", "category": "Groceries", "limit": 500}
\`\`\`

Only include an action block when the user explicitly asks to create or modify something. For informational questions, just answer normally without an action block. Use reasonable defaults for optional fields. For budget categories, use standard categories like: Groceries, Dining & Restaurants, Gas & Fuel, Rent & Mortgage, etc.

USER FINANCIAL SNAPSHOT:
${financialContext || 'No financial data available yet.'}`;

  const messages = [
    ...history.slice(-40).map(h => ({ role: h.role, content: h.content })),
    { role: 'user', content: message }
  ];

  try {
    const { default: Anthropic } = require('@anthropic-ai/sdk');
    const client = new Anthropic({ apiKey });
    const response = await client.messages.create({
      model: 'claude-sonnet-4-6', max_tokens: 1024, system: systemPrompt, messages
    });
    const text = response.content[0]?.text || '';
    res.json({ text, usage: response.usage, rateCount: getAiRateCount(req.user.id) });
  } catch (err) {
    res.status(500).json({ error: err.message || 'AI error' });
  }
});

// GET /api/ai/rate-limit — return current usage count
app.get('/api/ai/rate-limit', requireAuth, (req, res) => {
  res.json({ ok: true, count: getAiRateCount(req.user.id), limit: 50 });
});

// Serve upgrade page with Stripe publishable key + price ID injected
app.get('/upgrade', (_req, res) => {
  const fs   = require('fs');
  const html = fs.readFileSync(path.join(__dirname, '..', 'upgrade.html'), 'utf8');
  const config = `<script>
    window.__STRIPE_PUBLISHABLE_KEY__ = ${JSON.stringify(process.env.STRIPE_PUBLISHABLE_KEY || '')};
    window.__STRIPE_PRICE_ID__        = ${JSON.stringify(process.env.STRIPE_PRICE_ID || '')};
  </script>`;
  res.send(html.replace('</head>', config + '</head>'));
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

// Serve HTML files with no-cache so browsers always get the latest version
app.use(function(req, res, next) {
  if (req.path.endsWith('.html') || req.path === '/') {
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
  }
  next();
});

// Serve only the frontend files the web app needs (not the entire src/ directory)
const parentDir = path.join(__dirname, '..');
['style.css', 'plaid-link.html', 'index.html', 'icon.ico'].forEach(file => {
  app.get('/' + file, (_req, res) => res.sendFile(path.join(parentDir, file)));
});
// Serve app.html with Supabase config injected for token refresh
function serveApp(_req, res) {
  const fs = require('fs');
  const html = fs.readFileSync(path.join(parentDir, 'app.html'), 'utf8');
  const config = `<script>
    window.__SUPABASE_URL__      = ${JSON.stringify(process.env.SUPABASE_URL || '')};
    window.__SUPABASE_ANON_KEY__ = ${JSON.stringify(process.env.SUPABASE_ANON_KEY || '')};
  </script>`;
  res.send(html.replace('</head>', config + '</head>'));
}
app.get('/app.html', serveApp);
app.get('/', serveApp);

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

// AI feature routes — dispatches to domain modules
// POST /api/ai/:feature  { ...payload }
const TX_CATEGORIES = [
  'Income','Payroll & Wages','Freelance Income','Business Revenue','Interest & Dividends','Rental Income','Refunds',
  'Groceries','Dining & Restaurants','Fast Food','Coffee & Drinks','Alcohol & Bars',
  'Gas & Fuel','Auto Payment','Auto Insurance','Parking & Tolls','Rideshare & Taxi','Public Transit','Vehicle Maintenance',
  'Rent & Mortgage','Home Improvement','Furniture & Appliances','Household Supplies','HOA Fees',
  'Electric & Gas','Water & Sewer','Internet & Cable','Phone',
  'Health Insurance','Doctor & Medical','Pharmacy','Dental & Vision','Gym & Fitness','Mental Health',
  'Shopping','Clothing & Apparel','Electronics','Personal Care & Beauty','Pets','Gifts & Donations','Books & Hobbies',
  'Streaming & Subscriptions','Entertainment','Travel & Hotels','Flights','Vacation',
  'Childcare','Tuition & Student Loans','School Supplies',
  'Investments & Savings','Retirement','Credit Card Payment','Loan Payment','Life Insurance','Bank Fees',
  'Federal & State Taxes','Property Taxes','Tax Preparation',
  'Advertising & Marketing','Software & SaaS','Office Supplies','Professional Services','Legal & Accounting',
  'Business Insurance','Contractor & Freelance','Equipment & Hardware','Payroll',
  'Meals & Entertainment (Biz)','Business Travel','COGS','Inventory','Shipping & Fulfillment',
  'Transfer','Uncategorized','Other'
];

const aiDomainPath = path.join(__dirname, '..', 'domains', 'ai');

app.post('/api/ai/:feature', requireAuth, async (req, res) => {
  const feature = req.params.feature;
  const payload = req.body || {};

  try {
    switch (feature) {

      case 'categorize-transactions': {
        if (!checkAiRateLimit(req.user.id)) return res.status(429).json({ error: 'Daily AI limit reached' });
        const { transactions } = payload;
        if (!transactions || !transactions.length) return res.json([]);
        if (transactions.length > 100) return res.status(400).json({ error: 'Too many transactions (max 100 per batch)' });
        const apiKey = process.env.ANTHROPIC_API_KEY;
        if (!apiKey) return res.status(503).json({ error: 'No Anthropic API key configured.' });
        const { default: Anthropic } = require('@anthropic-ai/sdk');
        const client = new Anthropic({ apiKey });
        const categoryList = TX_CATEGORIES.join(', ');
        const lines = transactions.map((t, i) => `${i + 1}. ${t.desc}`).join('\n');
        const prompt = `You are a financial transaction categorizer for a personal finance app. Classify each transaction description into exactly one of these categories:\n${categoryList}\n\nGuidelines:\n- "Web Pmts", "Online Pmt", property management companies, and apartment/housing names are usually "Rent & Mortgage", not "Internet & Cable"\n- ACH transfers labeled with company names are usually bill payments — categorize by the company type, not the transfer method\n- "Transfer" should only be used for account-to-account transfers, not bill payments\n- Payments from payroll platforms like Deel, Gusto, ADP, Rippling are "Income", not "Contractor & Freelance" — these are employer salary deposits\n\nRespond with ONLY a JSON array of objects in this exact format, one per transaction, in order:\n[{"id":"<id>","category":"<category>"},...]\n\nTransactions:\n${lines}`;
        const idMap = transactions.map(t => t.id);
        const response = await client.messages.create({
          model: 'claude-haiku-4-5-20251001',
          max_tokens: 1024,
          messages: [{ role: 'user', content: prompt }]
        });
        const text = response.content[0]?.text || '[]';
        const jsonMatch = text.match(/\[[\s\S]*\]/);
        if (!jsonMatch) return res.json([]);
        let parsed;
        try { parsed = JSON.parse(jsonMatch[0]); } catch { return res.json([]); }
        return res.json(parsed.map((item, i) => ({
          id: idMap[i] || item.id,
          category: TX_CATEGORIES.includes(item.category) ? item.category : 'Other'
        })));
      }

      case 'forecast-cashflow': {
        const { forecastCashFlow } = require(path.join(aiDomainPath, 'cashFlowForecaster'));
        const { transactions = [], ...opts } = payload;
        const result = forecastCashFlow(transactions, opts);
        return res.json({ ok: true, ...result });
      }

      case 'detect-subscriptions': {
        const { detectSubscriptions } = require(path.join(aiDomainPath, 'subscriptionDetector'));
        const { transactions = [], ...opts } = payload;
        const result = detectSubscriptions(transactions, opts);
        return res.json({ ok: true, ...result });
      }

      case 'categorize-taxes': {
        const { categorizeTaxes } = require(path.join(aiDomainPath, 'taxCategorizer'));
        const { transactions = [], ...opts } = payload;
        const result = categorizeTaxes(transactions, opts);
        return res.json({ ok: true, ...result });
      }

      case 'project-net-worth': {
        const { projectNetWorth } = require(path.join(aiDomainPath, 'netWorthProjector'));
        const result = projectNetWorth(payload);
        return res.json({ ok: true, ...result });
      }

      case 'advise-goals': {
        const { adviseGoals } = require(path.join(aiDomainPath, 'goalAdvisor'));
        const result = adviseGoals(payload);
        return res.json({ ok: true, ...result });
      }

      case 'parse-search-query': {
        const { query, transactionSchema } = payload;
        if (!query || typeof query !== 'string') return res.status(400).json({ error: 'query string is required' });
        const apiKey = process.env.ANTHROPIC_API_KEY;
        if (!apiKey) return res.status(503).json({ error: 'No Anthropic API key configured.' });
        const { default: Anthropic } = require('@anthropic-ai/sdk');
        const client = new Anthropic({ apiKey });
        const schemaHint = transactionSchema
          ? `\nTransaction fields available: ${JSON.stringify(transactionSchema)}`
          : '\nTransaction fields: date (YYYY-MM-DD), amount (negative=expense), merchant_name, category, account_id';
        const message = await client.messages.create({
          model: 'claude-haiku-4-5',
          max_tokens: 512,
          messages: [{
            role: 'user',
            content: `Parse this transaction search query into a structured JSON filter object.${schemaHint}\n\nReturn ONLY valid JSON with these optional fields: { minAmount, maxAmount, merchant, category, startDate, endDate, isRecurring, accountId }.\n\nQuery: "${query}"`
          }]
        });
        const text = message.content[0]?.text ?? '';
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        if (!jsonMatch) return res.json({ ok: true, filter: {}, rawResponse: text });
        let filter;
        try { filter = JSON.parse(jsonMatch[0]); } catch { filter = {}; }
        return res.json({ ok: true, filter, query });
      }

      case 'advise-budget': {
        const { adviseBudget } = require(path.join(aiDomainPath, 'budgetAdvisor'));
        const result = adviseBudget(payload);
        return res.json({ ok: true, ...result });
      }

      case 'suggest-mileage': {
        const { suggestMileage } = require(path.join(aiDomainPath, 'mileageSuggestor'));
        const { transactions = [], ...opts } = payload;
        const result = suggestMileage(transactions, opts);
        return res.json({ ok: true, ...result });
      }

      case 'analyze-transaction': {
        const { analyzeTransaction, pushAlerts } = require(path.join(aiDomainPath, 'anomalyAlerts'));
        const { transaction, ...ctx } = payload;
        if (!transaction?.transaction_id) return res.status(400).json({ error: 'transaction.transaction_id is required' });
        const _buf = [];
        const alerts = analyzeTransaction(transaction, ctx);
        pushAlerts(alerts, { push: a => _buf.push(a) });
        return res.json({ ok: true, alerts });
      }

      case 'detect-trends': {
        const { detectTrends } = require(path.join(aiDomainPath, 'trendDetection'));
        const { transactions = [], ...opts } = payload;
        const trends = detectTrends(transactions, opts);
        return res.json({ ok: true, trends });
      }

      case 'debt-optimizer': {
        const { optimizeDebtPayoff } = require(path.join(aiDomainPath, 'debtOptimizer'));
        const result = optimizeDebtPayoff(payload);
        return res.json({ ok: true, ...result });
      }

      case 'queue-transaction': {
        // For web, process synchronously via pipeline rather than queue
        const { transaction, context = {} } = payload;
        if (!transaction || !transaction.transaction_id) {
          return res.status(400).json({ error: 'transaction.transaction_id is required' });
        }
        // Enqueue is fire-and-forget in desktop; for web just acknowledge
        return res.json({ queued: true, queueDepth: 0 });
      }

      case 'reprocess': {
        const { reprocessAll } = require(path.join(aiDomainPath, 'pipeline'));
        const storage = {
          async loadTransactions() { return []; },
          async saveFeatures() {},
          getFeatures() { return null; },
          getAllFeatures() { return []; },
          clearFeatures() {},
          async loadAccountContext() { return {}; },
        };
        const result = await reprocessAll(storage, { batchSize: payload.batchSize ?? 100 });
        return res.json({ ok: true, ...result });
      }

      default:
        return res.status(404).json({ error: `Unknown AI feature: ${feature}` });
    }
  } catch (err) {
    console.error(`[AI] /api/ai/${feature} error:`, err.message);
    return res.status(500).json({ error: 'AI processing failed' });
  }
});

// User app state — cross-browser persistence
// GET  /api/user/state  → returns stored state blob for this user
// PUT  /api/user/state  → saves state blob for this user
const { getUserState, saveUserState } = require('./db');

app.get('/api/user/state', requireAuth, (req, res) => {
  const state = getUserState(req.user.id);
  res.json({ state });
});

app.put('/api/user/state', requireAuth, (req, res) => {
  const { state } = req.body;
  if (!state || typeof state !== 'object') return res.status(400).json({ error: 'state object required' });
  saveUserState(req.user.id, state);
  res.json({ ok: true });
});

// Stripe routes — webhook mounted above (before json parser), rest require auth
app.use('/api/stripe', requireAuth, stripeRoutes);

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
