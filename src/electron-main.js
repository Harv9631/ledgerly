'use strict';

const { app, BrowserWindow, shell, ipcMain, safeStorage } = require('electron');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const Anthropic = require('@anthropic-ai/sdk');
const { registerIpcHandlers, makeFileStorage, shutdown } = require('./domains/ai/index');

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 900,
    minHeight: 600,
    title: 'Ledgerly',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js')
    },
    show: false
  });

  win.loadFile(path.join(__dirname, 'app.html'));

  win.once('ready-to-show', () => {
    win.show();
  });

  // Allow plaid-link.html to open as a new Electron window (needs window.opener for postMessage)
  // Open all other URLs (external links) in the system browser
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.includes('plaid-link.html')) {
      return {
        action: 'allow',
        overrideBrowserWindowOptions: {
          width: 500,
          height: 700,
          webPreferences: {
            nodeIntegration: false,
            contextIsolation: true,
            sandbox: false
          }
        }
      };
    }
    shell.openExternal(url);
    return { action: 'deny' };
  });
}

// --- Plaid backend proxy helpers ---
// All Plaid calls go through the Ledgerly server. No credentials on the client.

function getLedgerlyServerUrl() {
  try {
    const cfgPath = require('path').join(app.getPath('userData'), 'server-config.json');
    const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    return (cfg.serverUrl || 'http://localhost:3210').replace(/\/$/, '');
  } catch {
    return 'http://localhost:3210';
  }
}

async function serverFetch(path, options = {}) {
  const { net } = require('electron');
  const url = getLedgerlyServerUrl() + path;
  const method = options.method || 'GET';
  const body = options.body ? JSON.stringify(options.body) : undefined;

  return new Promise((resolve, reject) => {
    const request = net.request({ method, url });
    request.setHeader('Content-Type', 'application/json');
    request.setHeader('X-User-Id', 'ledgerly-user');
    const timer = setTimeout(() => {
      try { request.abort(); } catch {}
      reject(new Error('Server request timed out after 30s'));
    }, 30000);
    request.on('response', (response) => {
      let data = '';
      response.on('data', (chunk) => { data += chunk; });
      response.on('end', () => {
        clearTimeout(timer);
        try { resolve(JSON.parse(data)); } catch { resolve(data); }
      });
    });
    request.on('error', (err) => { clearTimeout(timer); reject(err); });
    if (body) request.write(body);
    request.end();
  });
}

// --- IPC handlers ---

ipcMain.handle('plaid:get-config', async () => {
  // No user-facing config needed — server holds credentials
  return { serverUrl: getLedgerlyServerUrl() };
});

ipcMain.handle('plaid:set-config', async (_event, { serverUrl }) => {
  try {
    const cfgPath = require('path').join(app.getPath('userData'), 'server-config.json');
    fs.writeFileSync(cfgPath, JSON.stringify({ serverUrl }, null, 2));
    return { ok: true };
  } catch (e) {
    return { error: e.message };
  }
});

ipcMain.handle('plaid:create-link-token', async () => {
  try {
    return await serverFetch('/api/plaid/link-token', { method: 'POST', body: {} });
  } catch (e) {
    return { error: e.message };
  }
});


// Open Plaid Link in the system browser via plaid-link.html (iframe approach).
// Electron's Chromium environment triggers Cloudflare bot-protection on cdn.plaid.com,
// causing an infinite spinner regardless of UA spoofing. The system browser handles
// Cloudflare challenges normally. plaid-link.html POSTs the result to the local server,
// and we poll here until it arrives.
ipcMain.handle('plaid:open-link', async (_event, token) => {
  return new Promise((resolve) => {
    let resolved = false;
    const finish = (result) => {
      if (resolved) return;
      resolved = true;
      clearInterval(poll);
      resolve(result);
    };

    const fallbackUrl = `http://localhost:3210/plaid-link.html?token=${encodeURIComponent(token)}`;
    logPlaid('Opening Plaid in system browser: ' + fallbackUrl.split('?')[0]);
    shell.openExternal(fallbackUrl);

    let attempts = 0;
    const poll = setInterval(async () => {
      if (resolved) { clearInterval(poll); return; }
      if (++attempts > 300) { clearInterval(poll); finish({ cancelled: true }); return; }
      try {
        const r = await serverFetch('/api/plaid/link-pending');
        if (r && r.public_token) { finish({ success: true, public_token: r.public_token, metadata: r.metadata || {} }); }
      } catch {}
    }, 1000);
  });
});


ipcMain.handle('plaid:exchange-token', async (_event, publicToken, metadata) => {
  try {
    return await serverFetch('/api/plaid/exchange-token', {
      method: 'POST',
      body: { public_token: publicToken, metadata: metadata || {} }
    });
  } catch (e) {
    return { error: e.message };
  }
});

ipcMain.handle('plaid:get-linked-items', async () => {
  try {
    return await serverFetch('/api/plaid/items');
  } catch (e) {
    return { error: e.message };
  }
});

ipcMain.handle('plaid:sync-accounts', async (_event, itemId) => {
  try {
    return await serverFetch(`/api/plaid/accounts/${itemId}`);
  } catch (e) {
    return { error: e.message };
  }
});

ipcMain.handle('plaid:sync-transactions', async (_event, itemId, reset) => {
  try {
    const url = `/api/plaid/sync/${itemId}` + (reset ? '?reset=true' : '');
    return await serverFetch(url, { method: 'POST', body: {} });
  } catch (e) {
    return { error: e.message };
  }
});

ipcMain.handle('plaid:remove-item', async (_event, itemId) => {
  try {
    return await serverFetch(`/api/plaid/items/${itemId}`, { method: 'DELETE' });
  } catch (e) {
    return { error: e.message };
  }
});

// --- AI Chat helpers ---

function getAiConfigPath() {
  return path.join(app.getPath('userData'), 'ai-config.json');
}

function getAiHistoryPath(conversationId) {
  const safe = (conversationId || 'default').replace(/[^a-z0-9_-]/gi, '_');
  return path.join(app.getPath('userData'), `ai-chat-${safe}.json`);
}

function getAiRateLimitPath() {
  return path.join(app.getPath('userData'), 'ai-rate-limit.json');
}

function getAiAuditLogPath() {
  return path.join(app.getPath('userData'), 'ai-audit.jsonl');
}

function writeAuditLogEntry(entry) {
  try {
    fs.appendFileSync(getAiAuditLogPath(), JSON.stringify(entry) + '\n');
  } catch {}
}

function purgeOldAuditLogEntries() {
  const logPath = getAiAuditLogPath();
  try {
    const raw = fs.readFileSync(logPath, 'utf8');
    const cutoff = Date.now() - 90 * 24 * 60 * 60 * 1000;
    const kept = raw.split('\n').filter(line => {
      if (!line.trim()) return false;
      try {
        return new Date(JSON.parse(line).timestamp).getTime() >= cutoff;
      } catch { return false; }
    });
    fs.writeFileSync(logPath, kept.length ? kept.join('\n') + '\n' : '');
  } catch {}
}

function readAiConfig() {
  try { return JSON.parse(fs.readFileSync(getAiConfigPath(), 'utf8')); } catch { return {}; }
}

// --- History encryption helpers ---

function getHistoryKeyPath() {
  return path.join(app.getPath('userData'), 'ai-chat-key.bin');
}

function getOrCreateHistoryKey() {
  const keyPath = getHistoryKeyPath();
  try {
    const key = fs.readFileSync(keyPath);
    if (key.length === 32) return key;
  } catch {}
  const key = crypto.randomBytes(32);
  fs.writeFileSync(keyPath, key);
  return key;
}

// Encrypted format: { version: 1, encrypted: "<base64>" }  -- safeStorage (OS keychain-backed)
//                   { version: 2, encrypted: "<base64>", iv: "<base64>", tag: "<base64>" }  -- AES-256-GCM fallback
// Legacy format: a plain JSON array (migrated transparently on next write)

function encryptHistory(history) {
  const json = JSON.stringify(history, null, 2);
  if (safeStorage.isEncryptionAvailable()) {
    const encrypted = safeStorage.encryptString(json);
    return JSON.stringify({ version: 1, encrypted: encrypted.toString('base64') });
  }
  // Fallback: AES-256-GCM with a machine-local key stored in userData
  const key = getOrCreateHistoryKey();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encBuf = Buffer.concat([cipher.update(json, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return JSON.stringify({
    version: 2,
    encrypted: encBuf.toString('base64'),
    iv: iv.toString('base64'),
    tag: tag.toString('base64')
  });
}

function decryptHistory(parsed) {
  if (Array.isArray(parsed)) return parsed; // legacy plain-text, migrated on next write
  if (!parsed || typeof parsed !== 'object') return [];
  if (parsed.version === 1) {
    try {
      const buf = Buffer.from(parsed.encrypted, 'base64');
      return JSON.parse(safeStorage.decryptString(buf));
    } catch { return []; }
  }
  if (parsed.version === 2) {
    try {
      const key = getOrCreateHistoryKey();
      const iv = Buffer.from(parsed.iv, 'base64');
      const tag = Buffer.from(parsed.tag, 'base64');
      const encBuf = Buffer.from(parsed.encrypted, 'base64');
      const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
      decipher.setAuthTag(tag);
      const json = Buffer.concat([decipher.update(encBuf), decipher.final()]).toString('utf8');
      return JSON.parse(json);
    } catch { return []; }
  }
  return [];
}

ipcMain.handle('ai:get-config', async () => {
  const cfg = readAiConfig();
  return { configured: !!cfg.apiKey };
});

ipcMain.handle('ai:set-config', async (_event, { apiKey }) => {
  try {
    fs.writeFileSync(getAiConfigPath(), JSON.stringify({ apiKey }, null, 2));
    return { ok: true };
  } catch (e) {
    return { error: e.message };
  }
});

ipcMain.handle('ai:get-history', async (_event, conversationId) => {
  try { return decryptHistory(JSON.parse(fs.readFileSync(getAiHistoryPath(conversationId), 'utf8'))); } catch { return []; }
});

ipcMain.handle('ai:clear-history', async (_event, conversationId) => {
  try { fs.unlinkSync(getAiHistoryPath(conversationId)); } catch {}
  return { ok: true };
});

ipcMain.handle('ai:get-rate-limit', async () => {
  try {
    const data = JSON.parse(fs.readFileSync(getAiRateLimitPath(), 'utf8'));
    const today = new Date().toISOString().slice(0, 10);
    if (data.date !== today) return { count: 0, limit: 50 };
    return { count: data.count, limit: 50 };
  } catch { return { count: 0, limit: 50 }; }
});

ipcMain.handle('ai:delete-all-data', async (_event, { deleteConfig = false } = {}) => {
  const userData = app.getPath('userData');
  const deleted = [];
  const errors = [];

  // Delete all ai-chat-*.json files
  try {
    const files = fs.readdirSync(userData);
    for (const file of files) {
      if (/^ai-chat-.+\.json$/.test(file)) {
        try {
          fs.unlinkSync(path.join(userData, file));
          deleted.push(file);
        } catch (e) {
          errors.push(`${file}: ${e.message}`);
        }
      }
    }
  } catch (e) {
    errors.push(`readdir: ${e.message}`);
  }

  // Delete ai-rate-limit.json
  try { fs.unlinkSync(getAiRateLimitPath()); deleted.push('ai-rate-limit.json'); } catch {}

  // Delete ai-audit.jsonl
  try { fs.unlinkSync(getAiAuditLogPath()); deleted.push('ai-audit.jsonl'); } catch {}

  // Delete ai-config.json (API key) only when explicitly requested
  if (deleteConfig) {
    try { fs.unlinkSync(getAiConfigPath()); deleted.push('ai-config.json'); } catch {}
  }

  // Clear in-memory feature store
  try { aiStorage.clearFeatures(); } catch {}

  return { ok: true, deleted, errors };
});

// Streaming chat handler (uses ipcMain.on, not handle, to allow mid-stream sends)
ipcMain.on('ai:chat', async (event, { message, conversationId, financialContext }) => {
  const config = readAiConfig();
  if (!config.apiKey) {
    event.sender.send('ai:chat-error', 'No Anthropic API key configured. Please add your key in Settings → AI Assistant.');
    return;
  }

  // Rate limiting: 50 messages/user/day
  const ratePath = getAiRateLimitPath();
  let rateData = {};
  try { rateData = JSON.parse(fs.readFileSync(ratePath, 'utf8')); } catch {}
  const today = new Date().toISOString().slice(0, 10);
  if (rateData.date !== today) rateData = { date: today, count: 0 };
  if (rateData.count >= 50) {
    event.sender.send('ai:chat-error', 'Daily limit reached (50 messages/day). Try again tomorrow.');
    return;
  }
  rateData.count++;
  fs.writeFileSync(ratePath, JSON.stringify(rateData, null, 2));

  // Load conversation history (last 40 messages = 20 turns)
  const histPath = getAiHistoryPath(conversationId);
  let history = [];
  try { history = decryptHistory(JSON.parse(fs.readFileSync(histPath, 'utf8'))); } catch {}

  const messages = history.slice(-40).map(h => ({ role: h.role, content: h.content }));
  messages.push({ role: 'user', content: message });

  const systemPrompt = `You are a personal financial advisor assistant inside Ledgerly, an income and debt tracking app. Help users understand their financial situation and provide actionable, data-driven advice.

CONSTRAINTS:
- Only answer questions related to personal finance, budgeting, debt management, savings, income, and financial planning.
- Do NOT advise on specific stock picks, securities trading, tax filing, or legal matters.
- Do NOT engage with topics unrelated to personal finance. Politely redirect if asked.
- Use the financial snapshot below to give personalized answers. Never reveal raw account numbers or identifiers.
- Be concise, encouraging, and practical.

USER FINANCIAL SNAPSHOT:
${financialContext || 'No financial data available yet.'}`;

  const auditBase = {
    timestamp: new Date().toISOString(),
    conversationId: conversationId || 'default',
    messageCount: messages.length
  };

  try {
    const client = new Anthropic({ apiKey: config.apiKey });
    const stream = client.messages.stream({
      model: 'claude-sonnet-4-6',
      max_tokens: 1024,
      system: systemPrompt,
      messages
    });

    let fullResponse = '';
    stream.on('text', (text) => {
      fullResponse += text;
      event.sender.send('ai:chat-chunk', text);
    });

    const finalMsg = await stream.finalMessage();

    // Persist history
    history.push({ role: 'user', content: message });
    history.push({ role: 'assistant', content: fullResponse });
    if (history.length > 40) history = history.slice(-40);
    fs.writeFileSync(histPath, encryptHistory(history));

    writeAuditLogEntry({
      ...auditBase,
      status: 'success',
      inputTokens: finalMsg.usage?.input_tokens ?? null,
      outputTokens: finalMsg.usage?.output_tokens ?? null
    });

    event.sender.send('ai:chat-done', { rateCount: rateData.count });
  } catch (err) {
    writeAuditLogEntry({ ...auditBase, status: 'error', error: err.message || 'unknown' });
    event.sender.send('ai:chat-error', err.message || 'Failed to connect to Claude API.');
  }
});

// --- AI: Batch transaction categorization ---
const TX_CATEGORIES_MAIN = ['Groceries','Dining','Transport','Entertainment','Shopping','Healthcare','Utilities','Rent/Housing','Insurance','Travel','Subscriptions','Education','Marketing','Payroll','Software','Income','Transfer','COGS','Personal Care & Beauty','Fitness & Sports','Pets','Childcare & Family','Gifts & Donations','Home Improvement & Maintenance','Investments & Savings','Taxes','Professional Services','Office Supplies','Equipment & Hardware','Contractor & Freelance','Shipping & Fulfillment','Inventory Purchases','Meals & Entertainment (Business)','Bank Fees & Financial Charges','Other'];

ipcMain.handle('ai:categorize-transactions', async (_event, { transactions }) => {
  const config = readAiConfig();
  if (!config.apiKey) throw new Error('No Anthropic API key configured. Please add your key in Settings → AI Assistant.');
  if (!transactions || !transactions.length) return [];

  const categoryList = TX_CATEGORIES_MAIN.join(', ');
  const lines = transactions.map((t, i) => `${i + 1}. ${t.desc}`).join('\n');
  const prompt = `You are a financial transaction categorizer. Classify each transaction description into exactly one of these categories:\n${categoryList}\n\nRespond with ONLY a JSON array of objects in this exact format, one per transaction, in order:\n[{"id":"<id>","category":"<category>"},...]\n\nTransactions:\n${lines}`;

  const idMap = transactions.map(t => t.id);

  const client = new Anthropic({ apiKey: config.apiKey });
  const response = await client.messages.create({
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 1024,
    messages: [{ role: 'user', content: prompt }]
  });

  const text = response.content[0]?.text || '[]';
  const jsonMatch = text.match(/\[[\s\S]*\]/);
  if (!jsonMatch) return [];

  const parsed = JSON.parse(jsonMatch[0]);
  // Map positional results back to original IDs
  return parsed.map((item, i) => ({
    id: idMap[i] || item.id,
    category: TX_CATEGORIES_MAIN.includes(item.category) ? item.category : 'Other'
  }));
});

// --- AI domain IPC ---

const aiStorage = makeFileStorage({ readTransactions: () => [] });
registerIpcHandlers(ipcMain, aiStorage);

function logPlaid(msg) {
  try {
    const logPath = path.join(app.getPath('userData'), 'plaid-debug.log');
    fs.appendFileSync(logPath, new Date().toISOString() + ' ' + msg + '\n');
  } catch {}
}

// --- Backend server auto-start ---

let serverProcess = null;

function startBackendServer() {
  // Check if server is already running before spawning to avoid EADDRINUSE
  const http = require('http');
  const check = http.request({ host: '127.0.0.1', port: 3210, path: '/health', timeout: 1000 }, () => {
    // Server already running — nothing to do
  });
  check.on('error', () => {
    // Server not running — spawn it.
    // In packaged builds the server lives in extraResources (process.resourcesPath);
    // in development it sits next to electron-main.js (__dirname).
    const { spawn } = require('child_process');
    const serverBase = app.isPackaged
      ? process.resourcesPath
      : __dirname;
    const serverScript = path.join(serverBase, 'server', 'index.js');
    const serverCwd    = path.join(serverBase, 'server');
    serverProcess = spawn(process.execPath, [serverScript], {
      cwd: serverCwd,
      stdio: 'ignore',
      env: { ...process.env, ELECTRON_RUN_AS_NODE: '1', PLAID_SDK_CACHE_DIR: app.getPath('userData'), DB_PATH: app.getPath('userData') }
    });
    serverProcess.on('error', () => {}); // suppress spawn errors silently
  });
  check.on('timeout', () => check.destroy());
  check.end();
}

// --- Plaid SDK cache ---
// Downloads link.js via electron.net (Chromium network stack) which bypasses the
// Cloudflare bot-protection that blocks plain Node.js HTTPS requests from the CDN.
// Re-downloads only when the cached file is older than 24 hours.

function cachePlaidSdk() {
  const { net } = require('electron');
  const cacheDir = app.getPath('userData');
  const cachePath = path.join(cacheDir, 'plaid-sdk.js');

  try {
    const stat = fs.statSync(cachePath);
    if (Date.now() - stat.mtimeMs < 24 * 60 * 60 * 1000) return; // still fresh
  } catch { /* file doesn't exist yet */ }

  const request = net.request('https://cdn.plaid.com/link/v2/stable/link-initialize.js');
  request.on('response', (response) => {
    if (response.statusCode !== 200) return;
    const chunks = [];
    response.on('data', (chunk) => chunks.push(chunk));
    response.on('end', () => {
      try { fs.writeFileSync(cachePath, Buffer.concat(chunks)); } catch {}
    });
  });
  request.on('error', () => {}); // non-fatal; SDK will fall back to CDN
  request.end();
}

// --- App lifecycle ---

app.whenReady().then(() => {
  purgeOldAuditLogEntries();
  cachePlaidSdk();
  startBackendServer();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  shutdown();
  if (serverProcess) serverProcess.kill();
});
