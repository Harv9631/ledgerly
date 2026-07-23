/* One-time helper: Jobber redirects here after the account owner approves
   the app. Exchanges the code for tokens and shows the refresh token so it
   can be stored as the JOBBER_REFRESH_TOKEN secret. Safe to leave deployed:
   without a fresh, unused authorization code it does nothing. */

const JOBBER_TOKEN_URL = "https://api.getjobber.com/api/oauth/token";

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  if (!code) return html("<h2>Missing ?code param — start at /api/jobber-connect</h2>", 400);

  const redirectUri = new URL("/api/jobber-callback", request.url).toString();
  const res = await fetch(JOBBER_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env.JOBBER_CLIENT_ID,
      client_secret: env.JOBBER_CLIENT_SECRET,
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri,
    }),
  });

  if (!res.ok) {
    const t = await res.text();
    return html(`<h2>Token exchange failed (${res.status})</h2><pre>${escapeHtml(t)}</pre>`, 502);
  }

  const body = await res.json();
  return html(`
    <h2>Jobber connected ✔</h2>
    <p>Copy both values below and paste them to Claude so they can be stored
       as deployment secrets. Then close this tab.</p>
    <h3>Refresh token (long-lived — this becomes JOBBER_REFRESH_TOKEN)</h3>
    <pre style="white-space:pre-wrap;word-break:break-all;background:#f4f4f4;padding:12px">${escapeHtml(body.refresh_token || "(none returned)")}</pre>
    <h3>Access token (expires in ~1 hour — used once for schema verification)</h3>
    <pre style="white-space:pre-wrap;word-break:break-all;background:#f4f4f4;padding:12px">${escapeHtml(body.access_token || "(none returned)")}</pre>
  `);
}

function html(bodyHtml, status = 200) {
  return new Response(
    `<!doctype html><meta charset="utf-8"><title>Jobber connection</title>
     <body style="font-family:system-ui;max-width:720px;margin:40px auto;padding:0 16px">${bodyHtml}</body>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8" } }
  );
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
