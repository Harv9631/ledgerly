/* Salty Air — website booking form → Jobber lead bridge.
   POST /api/book with the booking form JSON; creates a client + request
   in Jobber via GraphQL. Requires env secrets:
     JOBBER_CLIENT_ID, JOBBER_CLIENT_SECRET, JOBBER_REFRESH_TOKEN
   (refresh-token rotation must be OFF in the Jobber Developer Center app). */

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
    return json({ error: "Jobber auth failed" }, 502);
  }

  const name = String(data.name).trim();
  const spaceIdx = name.indexOf(" ");
  const firstName = spaceIdx > 0 ? name.slice(0, spaceIdx) : name;
  const lastName = spaceIdx > 0 ? name.slice(spaceIdx + 1) : "(no last name)";

  const clientRes = await gql(token, {
    query: `mutation CreateClient($attrs: ClientCreateAttributes!) {
      clientCreate(input: $attrs) {
        client { id }
        userErrors { message path }
      }
    }`,
    variables: {
      attrs: {
        firstName,
        lastName,
        emails: [{ description: "MAIN", primary: true, address: String(data.email).trim() }],
        phones: [{ description: "MAIN", primary: true, number: String(data.phone).trim() }],
      },
    },
  });

  const clientId = clientRes?.data?.clientCreate?.client?.id;
  if (!clientId) {
    return json(
      { error: "clientCreate failed", detail: clientRes?.data?.clientCreate?.userErrors || clientRes?.errors },
      502
    );
  }

  const details = [
    `WEBSITE BOOKING REQUEST`,
    ``,
    data.quote || "(no quote attached)",
    ``,
    `Address: ${data.address}`,
    `Preferred first date: ${data.preferred_date} (${data.preferred_time || "no time preference"})`,
    `Notes: ${data.notes || "—"}`,
  ].join("\n");

  const requestRes = await gql(token, {
    query: `mutation CreateRequest($attrs: RequestCreateAttributes!) {
      requestCreate(input: $attrs) {
        request { id }
        userErrors { message path }
      }
    }`,
    variables: {
      attrs: {
        clientId,
        title: `Website booking — ${name}`,
        details,
      },
    },
  });

  const requestId = requestRes?.data?.requestCreate?.request?.id;
  if (!requestId) {
    // Client exists but the request didn't attach — surface for debugging,
    // still a 502 so the front end tells the visitor to retry/email.
    return json(
      { error: "requestCreate failed", clientId, detail: requestRes?.data?.requestCreate?.userErrors || requestRes?.errors },
      502
    );
  }

  return json({ ok: true, clientId, requestId });
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
