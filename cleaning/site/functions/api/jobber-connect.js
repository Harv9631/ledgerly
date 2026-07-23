/* One-time helper: visit /api/jobber-connect to start the Jobber OAuth
   authorization for this site's Developer Center app. */

export async function onRequestGet({ request, env }) {
  if (!env.JOBBER_CLIENT_ID) {
    return new Response("JOBBER_CLIENT_ID secret is not set on this Pages project yet.", { status: 500 });
  }
  const redirectUri = new URL("/api/jobber-callback", request.url).toString();
  const state = crypto.randomUUID();
  const authUrl =
    "https://api.getjobber.com/api/oauth/authorize?" +
    new URLSearchParams({
      response_type: "code",
      client_id: env.JOBBER_CLIENT_ID,
      redirect_uri: redirectUri,
      state,
    });
  return Response.redirect(authUrl, 302);
}
