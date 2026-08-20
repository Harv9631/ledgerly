/* Salty Air — website booking form → Jobber lead bridge.
   POST /api/book with the booking form JSON; creates in Jobber:
     1. client (name, email, phone, property address)
     2. request titled "Website booking — <name>"
     3. pinned note on the request with the quote + preferences
   Env secrets: JOBBER_CLIENT_ID, JOBBER_CLIENT_SECRET, JOBBER_REFRESH_TOKEN
   (refresh-token rotation must stay OFF in the Jobber Developer Center app).
   Schema verified against X-JOBBER-GRAPHQL-VERSION 2025-04-16. */

const JOBBER_TOKEN_URL = "https://api.getjobber.com/api/oauth/token";
const JOBBER_GRAPHQL_URL = "https://api.getjobber.com/api/graphql";
const GRAPHQL_VERSION = "2025-04-16";

export async function onRequestPost({ request, env }) {
  let data;
  try {
    data = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  // Honeypot: hidden field real users never fill
  if (data.website) return json({ ok: true });

  const required = ["name", "phone", "email", "address", "preferred_date"];
  if (required.some((k) => !data[k] || !String(data[k]).trim())) {
    return json({ error: "Missing required fields" }, 400);
  }

  let token;
  try {
    token = await getAccessToken(env);
  } catch (e) {
    console.error("book: token refresh failed:", e.message);
    return json({ error: "Jobber auth failed" }, 502);
  }

  const name = String(data.name).trim();
  const spaceIdx = name.indexOf(" ");
  const firstName = spaceIdx > 0 ? name.slice(0, spaceIdx) : name;
  const lastName = spaceIdx > 0 ? name.slice(spaceIdx + 1) : "(no last name)";

  const clientMutation = `mutation CreateClient($input: ClientCreateInput!) {
    clientCreate(input: $input) {
      client { id }
      userErrors { message path }
    }
  }`;

  const buildClient = (smsAllowed) => ({
    firstName,
    lastName,
    emails: [{ description: "MAIN", primary: true, address: String(data.email).trim() }],
    phones: [{ description: "MAIN", primary: true, smsAllowed, number: String(data.phone).trim() }],
  });

  // Try most-complete input first, then degrade: Jobber rejects smsAllowed on
  // landlines and can reject unparseable addresses (address still lands in the note).
  const attempts = [
    { ...buildClient(true), properties: [{ address: parseAddress(data.address) }] },
    { ...buildClient(false), properties: [{ address: parseAddress(data.address) }] },
    buildClient(false),
  ];
  let clientRes, clientId;
  for (const input of attempts) {
    clientRes = await gql(token, { query: clientMutation, variables: { input } });
    clientId = clientRes?.data?.clientCreate?.client?.id;
    if (clientId) break;
  }
  if (!clientId) {
    console.error("book: clientCreate failed:", JSON.stringify(clientRes));
    return json(
      { error: "clientCreate failed", detail: clientRes?.data?.clientCreate?.userErrors || clientRes?.errors },
      502
    );
  }

  const requestRes = await gql(token, {
    query: `mutation CreateRequest($input: RequestCreateInput!) {
      requestCreate(input: $input) {
        request { id }
        userErrors { message path }
      }
    }`,
    variables: { input: { clientId, title: `Website booking — ${name}` } },
  });

  const requestId = requestRes?.data?.requestCreate?.request?.id;
  if (!requestId) {
    return json(
      { error: "requestCreate failed", clientId, detail: requestRes?.data?.requestCreate?.userErrors || requestRes?.errors },
      502
    );
  }

  const message = [
    "WEBSITE BOOKING REQUEST",
    "",
    data.quote || "(no quote attached)",
    "",
    `Address: ${data.address}`,
    `Preferred first date: ${data.preferred_date} (${data.preferred_time || "no time preference"})`,
    `Notes: ${data.notes || "—"}`,
  ].join("\n");

  const noteRes = await gql(token, {
    query: `mutation CreateNote($requestId: EncodedId!, $input: RequestCreateNoteInput!) {
      requestCreateNote(requestId: $requestId, input: $input) {
        requestNote { id }
        userErrors { message path }
      }
    }`,
    variables: { requestId, input: { message, pinned: true } },
  });

  const noteId = noteRes?.data?.requestCreateNote?.requestNote?.id;
  return json({
    ok: true,
    clientId,
    requestId,
    ...(noteId ? {} : { warning: "note failed", detail: noteRes?.data?.requestCreateNote?.userErrors || noteRes?.errors }),
  });
}

/* "123 Ocean Dr, Ponte Vedra Beach, FL 32082" → structured-ish address.
   Falls back to the whole string as street1. */
function parseAddress(raw) {
  const s = String(raw).trim();
  const parts = s.split(",").map((p) => p.trim()).filter(Boolean);
  const addr = { street1: parts[0] || s, province: "FL", country: "US" };
  if (parts.length >= 2) addr.city = parts[1].replace(/\b(FL|Florida)\b/i, "").replace(/\d{5}(-\d{4})?/, "").trim() || parts[1];
  const zip = s.match(/\b\d{5}(-\d{4})?\b/);
  if (zip) addr.postalCode = zip[0];
  return addr;
}

async function getAccessToken(env) {
  const res = await fetch(JOBBER_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env.JOBBER_CLIENT_ID,
      client_secret: env.JOBBER_CLIENT_SECRET,
      grant_type: "refresh_token",
      refresh_token: env.JOBBER_REFRESH_TOKEN,
    }),
  });
  if (!res.ok) throw new Error(`token refresh failed: ${res.status}`);
  const body = await res.json();
  if (!body.access_token) throw new Error("no access token in refresh response");
  return body.access_token;
}

async function gql(token, payload) {
  const res = await fetch(JOBBER_GRAPHQL_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `bearer ${token}`,
      "X-JOBBER-GRAPHQL-VERSION": GRAPHQL_VERSION,
    },
    body: JSON.stringify(payload),
  });
  return res.json();
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
