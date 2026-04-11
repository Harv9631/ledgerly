'use strict';

/**
 * Stripe subscription routes for Ledgerly web app.
 *
 * POST /api/stripe/checkout   — create a Checkout Session, returns { url }
 * POST /api/stripe/portal     — create a Customer Portal session, returns { url }
 * POST /api/stripe/webhook    — handle Stripe webhook events (no auth, uses sig verify)
 * GET  /api/stripe/status     — check if current user has active subscription
 */

const express = require('express');
const path    = require('path');
const router  = express.Router();

function getStripe() {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) throw new Error('STRIPE_SECRET_KEY not configured');
  return require('stripe')(key);
}

const { getUserState, saveUserState } = require('../db');

// ── GET /api/stripe/status ───────────────────────────────────────────────────
// Returns { active: bool, plan: string|null }
router.get('/status', (req, res) => {
  // Admin bypass — comma-separated user IDs or emails in ADMIN_USERS env var
  const adminList = (process.env.ADMIN_USERS || '').split(',').map(s => s.trim()).filter(Boolean);
  if (adminList.includes(req.user.id) || adminList.includes(req.user.email)) {
    return res.json({ active: true, plan: 'admin', trialEnd: null });
  }
  const userState = getUserState('stripe:' + req.user.id) || {};
  res.json({
    active: userState.active === true,
    plan: userState.plan || null,
    trialEnd: userState.trialEnd || null
  });
});

// ── POST /api/stripe/checkout ────────────────────────────────────────────────
// Creates a Stripe Checkout Session and returns the redirect URL.
// Body: { priceId, successUrl, cancelUrl }
router.post('/checkout', async (req, res) => {
  try {
    const stripe = getStripe();
    const { priceId } = req.body;
    if (!priceId) return res.status(400).json({ error: 'priceId required' });

    // Retrieve or create Stripe customer tied to this user
    const stripeState = getUserState('stripe:' + req.user.id) || {};
    let customerId = stripeState.customerId;

    if (!customerId) {
      const customer = await stripe.customers.create({
        metadata: { ledgerly_user_id: req.user.id, email: req.user.email || '' }
      });
      customerId = customer.id;
      saveUserState('stripe:' + req.user.id, { ...stripeState, customerId });
    }

    const origin = process.env.APP_URL || req.headers.origin || 'https://ledgerly-production-e022.up.railway.app';
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      mode: 'subscription',
      payment_method_types: ['card'],
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: origin + '/app.html?subscribed=1',
      cancel_url:  origin + '/upgrade.html',
      metadata: { ledgerly_user_id: req.user.id }
    });

    res.json({ url: session.url });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/stripe/portal ──────────────────────────────────────────────────
// Opens Stripe Customer Portal for managing/cancelling subscriptions.
router.post('/portal', async (req, res) => {
  try {
    const stripe = getStripe();
    const stripeState = getUserState('stripe:' + req.user.id) || {};
    if (!stripeState.customerId) return res.status(404).json({ error: 'No subscription found' });

    const origin = process.env.APP_URL || req.headers.origin || 'https://ledgerly-production-e022.up.railway.app';
    const session = await stripe.billingPortal.sessions.create({
      customer: stripeState.customerId,
      return_url: origin + '/app.html'
    });
    res.json({ url: session.url });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/stripe/webhook ─────────────────────────────────────────────────
// Stripe sends events here. Verifies signature and updates subscription status.
// Must be registered at stripe.com/webhooks with the endpoint URL.
router.post('/webhook', express.raw({ type: 'application/json' }), (req, res) => {
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  let event;

  if (!webhookSecret) {
    console.error('[STRIPE] STRIPE_WEBHOOK_SECRET not configured — rejecting webhook');
    return res.status(503).send('Webhook not configured');
  }

  const sig = req.headers['stripe-signature'];
  try {
    const stripe = getStripe();
    event = stripe.webhooks.constructEvent(req.body, sig, webhookSecret);
  } catch (err) {
    return res.status(400).send('Webhook signature verification failed');
  }

  const obj = event.data.object;
  const userId = obj.metadata?.ledgerly_user_id || (obj.customer ? findUserByCustomer(obj.customer) : null);

  if (userId) {
    const stripeKey = 'stripe:' + userId;
    const current = getUserState(stripeKey) || {};

    if (event.type === 'checkout.session.completed') {
      saveUserState(stripeKey, { ...current, active: true, plan: 'pro', subscriptionId: obj.subscription });
    } else if (event.type === 'customer.subscription.updated') {
      const active = ['active', 'trialing'].includes(obj.status);
      saveUserState(stripeKey, { ...current, active, plan: active ? 'pro' : null, status: obj.status });
    } else if (event.type === 'customer.subscription.deleted') {
      saveUserState(stripeKey, { ...current, active: false, plan: null });
    }
  }

  res.json({ received: true });
});

function findUserByCustomer(customerId) {
  // Look up which user owns this Stripe customer ID by scanning user states
  const fs = require('fs');
  const dbDir = process.env.DB_PATH || path.join(__dirname, '..');
  const dbFile = path.join(dbDir, 'ledgerly-data.json');
  try {
    const data = JSON.parse(fs.readFileSync(dbFile, 'utf8'));
    const states = data.user_states || {};
    for (const [key, val] of Object.entries(states)) {
      if (key.startsWith('stripe:') && val.customerId === customerId) {
        return key.slice(7); // strip 'stripe:' prefix to get user ID
      }
    }
  } catch {}
  return null;
}

module.exports = router;
