/* TEMPORARY admin helper — list & edit Jobber Products and Services prices.
   Guarded by a random key; delete this file after the one-time price sync.
   GET  ?key=…              → list all products/services with prices
   GET  ?key=…&introspect=1 → introspect the edit mutation shape
   POST ?key=…  body {updates:[{id, cost}]} → set defaultUnitCost per item */

const KEY = "15a8a97af21d05ba1eee5a1a66ce957b234cf097";
const JOBBER_TOKEN_URL = "https://api.getjobber.com/api/oauth/token";
const JOBBER_GRAPHQL_URL = "https://api.getjobber.com/api/graphql";
const GRAPHQL_VERSION = "2025-04-16";

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  if (url.searchParams.get("key") !== KEY) return json({ error: "forbidden" }, 403);
  const token = await getAccessToken(env);

  if (url.searchParams.get("introspect")) {
    const res = await gql(token, {
      query: `{
        mutations: __type(name: "Mutation") { fields { name } }
        editInput: __type(name: "ProductsAndServicesEditInput") {
          inputFields { name type { name kind ofType { name } } }
        }
      }`,
    });
    return json(res);
  }

  const res = await gql(token, {
    query: `{
      productOrServices(first: 100) {
        nodes { id name description category defaultUnitCost durationMinutes visible }
      }
    }`,
  });
  return json(res);
}

export async function onRequestPost({ request, env }) {
  const url = new URL(request.url);
  if (url.searchParams.get("key") !== KEY) return json({ error: "forbidden" }, 403);
  const { updates } = await request.json();
  if (!Array.isArray(updates)) return json({ error: "updates array required" }, 400);
  const token = await getAccessToken(env);

  const results = [];
  for (const u of updates) {
    const res = await gql(token, {
      query: `mutation EditPrice($id: EncodedId!, $input: ProductsAndServicesEditInput!) {
        productsAndServicesEdit(productsAndServicesId: $id, input: $input) {
          productOrService { id name defaultUnitCost }
          userErrors { message path }
        }
      }`,
      variables: { id: u.id, input: { defaultUnitCost: u.cost } },
    });
    results.push(res);
  }
  return json({ results });
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
  return (await res.json()).access_token;
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
  return new Response(JSON.stringify(obj, null, 2), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
