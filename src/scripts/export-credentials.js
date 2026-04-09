'use strict';
// Run with: electron scripts/export-credentials.js
// Decrypts stored Plaid credentials and writes them to server/.env

const { app, safeStorage } = require('electron');
const path = require('path');
const fs   = require('fs');

app.whenReady().then(() => {
  try {
    const credPath = path.join(process.env.APPDATA, 'Ledgerly', 'plaid-credentials.json');
    const data = JSON.parse(fs.readFileSync(credPath, 'utf8'));
    let creds;
    if (data.encrypted) {
      creds = JSON.parse(safeStorage.decryptString(Buffer.from(data.encrypted, 'base64')));
    } else {
      creds = data;
    }

    const envPath = path.join(__dirname, '..', 'server', '.env');
    const supabaseUrl  = process.env.SUPABASE_URL  || 'https://phkgapawikotezvlyyho.supabase.co';
    const supabaseKey  = process.env.SUPABASE_ANON_KEY || 'sb_publishable_LXRsoqRWt_9Du0bSuDzeWQ_EzC6O25r';

    const envContent = [
      'PLAID_CLIENT_ID=' + creds.clientId,
      'PLAID_SECRET='    + creds.secret,
      'PLAID_ENV='       + (creds.environment || 'development'),
      'SUPABASE_URL='    + supabaseUrl,
      'SUPABASE_ANON_KEY=' + supabaseKey,
    ].join('\n') + '\n';

    fs.writeFileSync(envPath, envContent);
    console.log('✓ Wrote credentials to server/.env');
    console.log('  PLAID_ENV:', creds.environment);
    console.log('  CLIENT_ID:', creds.clientId ? creds.clientId.slice(0,6) + '...' : 'missing');
  } catch (err) {
    console.error('Error:', err.message);
  }
  app.quit();
});
