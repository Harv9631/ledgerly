'use strict';

const express = require('express');
const { Configuration, PlaidApi, PlaidEnvironments } = require('plaid');
const db = require('../db');

const router = express.Router();

function buildPlaidClient() {
  const env = process.env.PLAID_ENV || 'sandbox';
  const configuration = new Configuration({
    basePath: PlaidEnvironments[env],
    baseOptions: {
      headers: {
        'PLAID-CLIENT-ID': process.env.PLAID_CLIENT_ID,
        'PLAID-SECRET': process.env.PLAID_SECRET
      }
    }
  });
  return new PlaidApi(configuration);
}

// User ID comes from auth middleware (Supabase JWT) or fallback for Electron dev
function getUserId(req) {
  return (req.user && req.user.id) || req.headers['x-user-id'] || 'default';
}

// In-process store for Plaid Link callback (consumed once, expires after 5 min)
let _pendingLink = null;
let _pendingLinkTimer = null;

// POST /api/plaid/link-callback — called by plaid-link.html (legacy IPC path)
router.post('/link-callback', (req, res) => {
  const { public_token, metadata } = req.body;
  if (_pendingLinkTimer) clearTimeout(_pendingLinkTimer);
  _pendingLink = { public_token, metadata };
  _pendingLinkTimer = setTimeout(() => { _pendingLink = null; }, 300000);
  res.json({ ok: true });
});

// GET /plaid-redirect — Plaid redirects here after the user completes Link in their browser.
// The public_token is passed as a query param. Plaid docs confirm localhost URIs are
// permitted in all environments without dashboard registration.
router.get('/redirect', (req, res) => {
  const { public_token, metadata } = req.query;
  if (public_token) {
    if (_pendingLinkTimer) clearTimeout(_pendingLinkTimer);
    _pendingLink = { public_token, metadata: metadata ? JSON.parse(decodeURIComponent(metadata)) : {} };
    _pendingLinkTimer = setTimeout(() => { _pendingLink = null; }, 300000);
  }
  // Serve a close-me page so the browser tab closes itself
  res.send(`<!DOCTYPE html><html><head><title>Connected!</title></head><body>
    <p style="font-family:sans-serif;margin:40px auto;max-width:400px;text-align:center">
      Bank connected successfully!<br><br>You can close this tab and return to Ledgerly.
    </p>
    <script>try{window.close();}catch(e){}</script>
  </body></html>`);
});

// GET /api/plaid/link-pending — polled by Electron to retrieve the result
router.get('/link-pending', (req, res) => {
  if (_pendingLink) {
    const result = _pendingLink;
    _pendingLink = null;
    if (_pendingLinkTimer) clearTimeout(_pendingLinkTimer);
    res.json(result);
  } else {
    res.json(null);
  }
});

// POST /api/plaid/link-token
// Create a Plaid Link token for the current user.
// No redirect_uri — the link-initialize.js SDK handles OAuth banks via popup windows,
// so no redirect URI is needed for this desktop web context.
router.post('/link-token', async (req, res) => {
  try {
    const client = buildPlaidClient();
    const userId = getUserId(req);
    const response = await client.linkTokenCreate({
      user: { client_user_id: userId },
      client_name: 'Ledgerly',
      products: ['transactions'],
      country_codes: ['US'],
      language: 'en'
    });
    res.json(response.data);
  } catch (err) {
    const msg = err.response?.data?.error_message || err.message;
    res.status(500).json({ error: msg });
  }
});

// POST /api/plaid/exchange-token
// Exchange a Plaid public_token for an access token and store it
router.post('/exchange-token', async (req, res) => {
  try {
    const { public_token, metadata } = req.body;
    if (!public_token) return res.status(400).json({ error: 'public_token required' });

    const client = buildPlaidClient();
    const userId = getUserId(req);

    const response = await client.itemPublicTokenExchange({ public_token });
    const { access_token, item_id } = response.data;

    const institutionId = metadata?.institution?.institution_id || null;
    const institutionName = metadata?.institution?.name || null;

    await db.query(
      `INSERT INTO plaid_items (item_id, user_id, access_token, institution_id, institution_name)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (item_id) DO UPDATE
         SET access_token = excluded.access_token,
             status = 'active',
             updated_at = datetime('now')`,
      [item_id, userId, access_token, institutionId, institutionName]
    );

    res.json({ item_id, institution_name: institutionName });
  } catch (err) {
    const msg = err.response?.data?.error_message || err.message;
    res.status(500).json({ error: msg });
  }
});

// GET /api/plaid/items
// List linked items for the current user
// Auto-migrates legacy data from 'web-user-default' to the real user ID if needed
router.get('/items', async (req, res) => {
  try {
    const userId = getUserId(req);
    const result = await db.query(
      `SELECT item_id, institution_id, institution_name, status, created_at
       FROM plaid_items WHERE user_id = $1 ORDER BY created_at DESC`,
      [userId]
    );
    // If no items found and user is not the legacy ID, check for legacy data to migrate
    if (!result.rows.length && userId !== 'web-user-default') {
      const legacy = await db.query(
        `SELECT item_id, institution_id, institution_name, status, created_at
         FROM plaid_items WHERE user_id = $1 ORDER BY created_at DESC`,
        ['web-user-default']
      );
      if (legacy.rows.length) {
        // Migrate legacy items to the real user ID
        for (const item of legacy.rows) {
          await db.query(
            `UPDATE plaid_items SET user_id = $1 WHERE item_id = $2 AND user_id = 'web-user-default'`,
            [userId, item.item_id]
          ).catch(() => {});
        }
        console.log('[PLAID] Migrated', legacy.rows.length, 'items from web-user-default to', userId.slice(0, 8) + '...');
        return res.json(legacy.rows);
      }
    }
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/plaid/accounts/:itemId
// Fetch accounts and balances for a linked item
router.get('/accounts/:itemId', async (req, res) => {
  try {
    const userId = getUserId(req);
    const { itemId } = req.params;

    const itemResult = await db.query(
      'SELECT access_token FROM plaid_items WHERE item_id = $1 AND user_id = $2',
      [itemId, userId]
    );
    if (!itemResult.rows.length) return res.status(404).json({ error: 'Item not found' });

    const client = buildPlaidClient();
    const response = await client.accountsGet({ access_token: itemResult.rows[0].access_token });
    res.json(response.data);
  } catch (err) {
    const msg = err.response?.data?.error_message || err.message;
    res.status(500).json({ error: msg });
  }
});

// POST /api/plaid/sync/:itemId
// Sync transactions for a linked item (cursor-based, paginated).
// Pass ?reset=true to clear the cursor and re-fetch all historical transactions from scratch.
router.post('/sync/:itemId', async (req, res) => {
  try {
    const userId = getUserId(req);
    const { itemId } = req.params;
    const reset = req.query.reset === 'true';

    const itemResult = await db.query(
      'SELECT access_token, cursor FROM plaid_items WHERE item_id = $1 AND user_id = $2',
      [itemId, userId]
    );
    if (!itemResult.rows.length) return res.status(404).json({ error: 'Item not found' });

    const { access_token } = itemResult.rows[0];
    const cursor = reset ? undefined : itemResult.rows[0].cursor;
    const client = buildPlaidClient();

    let nextCursor = cursor;
    let added = [], modified = [], removed = [], hasMore = true;

    while (hasMore) {
      const response = await client.transactionsSync({
        access_token,
        cursor: nextCursor || undefined
      });
      const data = response.data;
      added = added.concat(data.added);
      modified = modified.concat(data.modified);
      removed = removed.concat(data.removed);
      nextCursor = data.next_cursor;
      hasMore = data.has_more;
    }

    // Persist cursor
    await db.query(
      "UPDATE plaid_items SET cursor = $1, updated_at = datetime('now') WHERE item_id = $2",
      [nextCursor, itemId]
    );

    // Upsert accounts and transactions into DB (best-effort, non-blocking errors)
    try {
      for (const tx of added) {
        // Ensure account exists
        await db.query(
          `INSERT INTO accounts (account_id, item_id, name, type, subtype)
           VALUES ($1, $2, $3, 'unknown', 'unknown')
           ON CONFLICT (account_id) DO NOTHING`,
          [tx.account_id, itemId, tx.account_id]
        );
        await db.query(
          `INSERT INTO transactions
             (transaction_id, account_id, amount, date, name, merchant_name, pending, raw_plaid_data)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
           ON CONFLICT (transaction_id) DO UPDATE
             SET amount = excluded.amount, pending = excluded.pending,
                 merchant_name = excluded.merchant_name, updated_at = datetime('now')`,
          [tx.transaction_id, tx.account_id, tx.amount, tx.date,
           tx.name, tx.merchant_name || null, tx.pending, JSON.stringify(tx)]
        );
      }
      for (const tx of modified) {
        await db.query(
          `UPDATE transactions SET amount = $1, pending = $2, merchant_name = $3,
             raw_plaid_data = $4, updated_at = datetime('now')
           WHERE transaction_id = $5`,
          [tx.amount, tx.pending, tx.merchant_name || null, JSON.stringify(tx), tx.transaction_id]
        );
      }
      for (const tx of removed) {
        await db.query('DELETE FROM transactions WHERE transaction_id = $1', [tx.transaction_id]);
      }
    } catch (dbErr) {
      // Log but don't fail — return results to client regardless
      console.error('DB upsert error (non-fatal):', dbErr.message);
    }

    res.json({ added, modified, removed });
  } catch (err) {
    const msg = err.response?.data?.error_message || err.message;
    // Mark item as needing re-auth if Plaid says so
    if (err.response?.data?.error_code === 'ITEM_LOGIN_REQUIRED') {
      await db.query(
        "UPDATE plaid_items SET status = 'item_login_required', updated_at = datetime('now') WHERE item_id = $1",
        [req.params.itemId]
      ).catch(() => {});
    }
    res.status(500).json({ error: msg });
  }
});

// DELETE /api/plaid/items/:itemId
// Remove a linked item
router.delete('/items/:itemId', async (req, res) => {
  try {
    const userId = getUserId(req);
    const { itemId } = req.params;

    // Verify item belongs to the authenticated user before deleting
    const itemResult = await db.query(
      'SELECT access_token FROM plaid_items WHERE item_id = $1 AND user_id = $2',
      [itemId, userId]
    );
    if (!itemResult.rows.length) return res.status(404).json({ error: 'Item not found' });

    try {
      const client = buildPlaidClient();
      await client.itemRemove({ access_token: itemResult.rows[0].access_token });
    } catch {} // Plaid removal is best-effort

    await db.query('DELETE FROM plaid_items WHERE item_id = $1 AND user_id = $2', [itemId, userId]);

    res.json({ ok: true });
  } catch (err) {
    const msg = err.response?.data?.error_message || err.message;
    res.status(500).json({ error: msg });
  }
});

// POST /api/plaid/webhook
// Plaid webhook receiver — handles real-time notifications
// Validates that the item_id exists in our database before acting on any event.
router.post('/webhook', async (req, res) => {
  const { webhook_type, webhook_code, item_id } = req.body;

  // Reject requests missing required fields
  if (!webhook_type || !webhook_code || !item_id) {
    return res.status(400).json({ error: 'Invalid webhook payload' });
  }

  // Only process events for items we actually have — prevents spoofed item_ids
  const itemResult = await db.query(
    'SELECT item_id FROM plaid_items WHERE item_id = $1',
    [item_id]
  );
  if (!itemResult.rows.length) {
    console.log(`Plaid webhook: ignoring unknown item ${item_id}`);
    return res.json({ ok: true });
  }

  console.log(`Plaid webhook: ${webhook_type}/${webhook_code} for item ${item_id}`);

  // Only act on recognized webhook codes
  if (webhook_code === 'SYNC_UPDATES_AVAILABLE') {
    await db.query(
      "UPDATE plaid_items SET updated_at = datetime('now') WHERE item_id = $1",
      [item_id]
    ).catch(() => {});
  } else if (webhook_code === 'PENDING_EXPIRATION' || webhook_code === 'ERROR') {
    await db.query(
      "UPDATE plaid_items SET status = 'item_login_required', updated_at = datetime('now') WHERE item_id = $1",
      [item_id]
    ).catch(() => {});
  }

  res.json({ ok: true });
});

// Exported for use by server/index.js /plaid-redirect route
module.exports = router;
module.exports.setPendingLink = function(data) {
  if (_pendingLinkTimer) clearTimeout(_pendingLinkTimer);
  _pendingLink = data;
  _pendingLinkTimer = setTimeout(function() { _pendingLink = null; }, 300000);
};
