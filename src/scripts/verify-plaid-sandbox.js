'use strict';

/**
 * Plaid Sandbox Connectivity Verification
 * Run: node scripts/verify-plaid-sandbox.js
 *
 * Requires .env in project root with:
 *   PLAID_CLIENT_ID, PLAID_SECRET, PLAID_ENV (sandbox)
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const { Configuration, PlaidApi, PlaidEnvironments } = require('plaid');

const REQUIRED_VARS = ['PLAID_CLIENT_ID', 'PLAID_SECRET', 'PLAID_ENV'];

function checkEnv() {
  const missing = REQUIRED_VARS.filter(v => !process.env[v]);
  if (missing.length > 0) {
    console.error('Missing required environment variables:', missing.join(', '));
    console.error('Copy .env.example to .env and fill in your Plaid sandbox credentials.');
    process.exit(1);
  }
}

async function verifySandbox() {
  checkEnv();

  const env = process.env.PLAID_ENV;
  const plaidEnv = PlaidEnvironments[env];
  if (!plaidEnv) {
    console.error(`Invalid PLAID_ENV="${env}". Must be one of: sandbox, development, production`);
    process.exit(1);
  }

  console.log(`\nPlaid Sandbox Verification`);
  console.log(`==========================`);
  console.log(`Environment : ${env}`);
  console.log(`Client ID   : ${process.env.PLAID_CLIENT_ID}`);
  console.log(`API URL     : ${plaidEnv}`);
  console.log('');

  const config = new Configuration({
    basePath: plaidEnv,
    baseOptions: {
      headers: {
        'PLAID-CLIENT-ID': process.env.PLAID_CLIENT_ID,
        'PLAID-SECRET': process.env.PLAID_SECRET,
      },
    },
  });

  const client = new PlaidApi(config);

  // Step 1: Create a sandbox public token (simulates a user connecting their bank)
  console.log('Step 1: Creating sandbox public token...');
  let publicToken;
  try {
    const response = await client.sandboxPublicTokenCreate({
      institution_id: 'ins_109508', // First Platypus Bank (Plaid test institution)
      initial_products: ['transactions', 'liabilities'],
    });
    publicToken = response.data.public_token;
    console.log(`  ✓ public_token created: ${publicToken.substring(0, 30)}...`);
  } catch (err) {
    console.error('  ✗ Failed to create sandbox public token');
    console.error('  Error:', err.response?.data?.error_message || err.message);
    if (err.response?.data?.error_code === 'INVALID_API_KEYS') {
      console.error('\n  → Your PLAID_CLIENT_ID or PLAID_SECRET is incorrect.');
      console.error('  → Get them from: https://dashboard.plaid.com/team/keys');
    }
    process.exit(1);
  }

  // Step 2: Exchange public token for access token
  console.log('Step 2: Exchanging public token for access token...');
  let accessToken, itemId;
  try {
    const response = await client.itemPublicTokenExchange({ public_token: publicToken });
    accessToken = response.data.access_token;
    itemId = response.data.item_id;
    console.log(`  ✓ access_token: ${accessToken.substring(0, 35)}...`);
    console.log(`  ✓ item_id: ${itemId}`);
  } catch (err) {
    console.error('  ✗ Failed to exchange token');
    console.error('  Error:', err.response?.data?.error_message || err.message);
    process.exit(1);
  }

  // Step 3: Fetch accounts to confirm connection works
  console.log('Step 3: Fetching accounts...');
  try {
    const response = await client.accountsGet({ access_token: accessToken });
    const accounts = response.data.accounts;
    console.log(`  ✓ ${accounts.length} account(s) returned:`);
    accounts.forEach(acct => {
      console.log(`    - [${acct.type}/${acct.subtype}] ${acct.name} — balance: $${acct.balances.current}`);
    });
  } catch (err) {
    console.error('  ✗ Failed to fetch accounts');
    console.error('  Error:', err.response?.data?.error_message || err.message);
    process.exit(1);
  }

  // Step 4: Test transactions sync
  console.log('Step 4: Testing transactions sync...');
  try {
    const response = await client.transactionsSync({ access_token: accessToken });
    const added = response.data.added;
    console.log(`  ✓ ${added.length} transaction(s) returned from initial sync`);
    if (added.length > 0) {
      const first = added[0];
      console.log(`    Sample: ${first.name} — $${first.amount} on ${first.date}`);
    }
  } catch (err) {
    console.error('  ✗ Failed to sync transactions');
    console.error('  Error:', err.response?.data?.error_message || err.message);
    process.exit(1);
  }

  console.log('\n✅ Plaid sandbox connectivity verified successfully!');
  console.log('   All 4 steps passed. Integration is ready for development.\n');
}

verifySandbox().catch(err => {
  console.error('Unexpected error:', err.message);
  process.exit(1);
});
