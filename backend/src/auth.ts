import { Hono } from "hono";
import type { Context, MiddlewareHandler } from "hono";
import { fromBase64, nowSeconds, randomToken, sha256Base64url, sha256Hex, signPayload, timingSafeEqual, verifyPayload } from "./crypto";
import { createSession, deleteSession, upsertGoogleUser, userForToken } from "./db";
import type { AppContext } from "./env";

const GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const STATE_TTL_SECONDS = 10 * 60;
const LOGIN_CODE_TTL_SECONDS = 5 * 60;
const APP_STATE_RE = /^[A-Za-z0-9_-]{8,128}$/;
const CHALLENGE_RE = /^[A-Za-z0-9_-]{43}$/;

interface OAuthState {
  app_state: string;
  code_challenge: string;
  exp: number;
}

export function publicOrigin(c: Context<AppContext>): string {
  return c.env.PUBLIC_URL || new URL(c.req.url).origin;
}

export const auth = new Hono<AppContext>();

/** Step 1: the app opens this in the browser; we send the user to Google. */
auth.get("/google/start", async (c) => {
  const appState = c.req.query("app_state") ?? "";
  const challenge = c.req.query("code_challenge") ?? "";
  if (!APP_STATE_RE.test(appState) || !CHALLENGE_RE.test(challenge)) {
    return c.text("Invalid sign-in request. Please try again from the Hear Agent app.", 400);
  }
  const state = await signPayload(c.env.STATE_SECRET, {
    app_state: appState,
    code_challenge: challenge,
    exp: nowSeconds() + STATE_TTL_SECONDS,
  } satisfies OAuthState);
  const url = new URL(GOOGLE_AUTH_URL);
  url.search = new URLSearchParams({
    client_id: c.env.GOOGLE_CLIENT_ID,
    redirect_uri: `${publicOrigin(c)}/auth/google/callback`,
    response_type: "code",
    scope: "openid email profile",
    state,
    prompt: "select_account",
  }).toString();
  return c.redirect(url.toString(), 302);
});

/** Step 2: Google sends the user back here; we hand the app a one-time code. */
auth.get("/google/callback", async (c) => {
  const state = await verifyPayload<OAuthState>(c.env.STATE_SECRET, c.req.query("state") ?? "");
  if (!state || state.exp < nowSeconds()) {
    return page(c, "Sign-in expired", "Please start again from the Hear Agent app.", 400);
  }
  if (c.req.query("error")) {
    return page(c, "Sign-in cancelled", "You can close this tab and try again from Hear Agent.", 400);
  }
  const code = c.req.query("code");
  if (!code) return page(c, "Sign-in failed", "Google did not return a code.", 400);

  const tokenResponse = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: c.env.GOOGLE_CLIENT_ID,
      client_secret: c.env.GOOGLE_CLIENT_SECRET,
      redirect_uri: `${publicOrigin(c)}/auth/google/callback`,
      grant_type: "authorization_code",
    }),
  });
  if (!tokenResponse.ok) {
    console.log(JSON.stringify({ event: "google_token_error", status: tokenResponse.status }));
    return page(c, "Sign-in failed", "Google rejected the sign-in. Please try again.", 502);
  }
  const { id_token } = await tokenResponse.json<{ id_token?: string }>();
  const claims = id_token ? googleClaims(id_token, c.env.GOOGLE_CLIENT_ID) : null;
  if (!claims) return page(c, "Sign-in failed", "Could not verify your Google account.", 502);

  const user = await upsertGoogleUser(c.env.DB, claims.sub, claims.email, claims.name ?? "");
  const loginCode = randomToken(32);
  await c.env.DB.prepare("INSERT INTO login_codes (code_hash, user_id, code_challenge, expires_at) VALUES (?1, ?2, ?3, ?4)")
    .bind(await sha256Hex(loginCode), user.id, state.code_challenge, nowSeconds() + LOGIN_CODE_TTL_SECONDS)
    .run();

  const appUrl = `${c.env.APP_URL_SCHEME}://auth?code=${encodeURIComponent(loginCode)}&state=${encodeURIComponent(state.app_state)}`;
  return page(c, "Signed in", "Returning to Hear Agent…", 200, appUrl);
});

/** Step 3: the app trades the one-time code plus its PKCE verifier for a session token. */
auth.post("/exchange", async (c) => {
  const body = await c.req.json<{ code?: string; code_verifier?: string }>().catch(() => ({}) as Record<string, never>);
  if (!body.code || !body.code_verifier) return c.json({ error: "invalid_request" }, 400);
  const codeHash = await sha256Hex(body.code);
  const row = await c.env.DB.prepare("DELETE FROM login_codes WHERE code_hash = ?1 RETURNING user_id, code_challenge, expires_at")
    .bind(codeHash)
    .first<{ user_id: string; code_challenge: string; expires_at: number }>();
  if (!row || row.expires_at < nowSeconds()) return c.json({ error: "invalid_code" }, 400);
  if (!timingSafeEqual(await sha256Base64url(body.code_verifier), row.code_challenge)) {
    return c.json({ error: "invalid_code" }, 400);
  }
  return c.json({ token: await createSession(c.env.DB, row.user_id) });
});

auth.post("/sign-out", async (c) => {
  const token = bearer(c);
  if (token) await deleteSession(c.env.DB, token);
  return c.json({ ok: true });
});

export const requireUser: MiddlewareHandler<AppContext> = async (c, next) => {
  const token = bearer(c);
  const user = token ? await userForToken(c.env.DB, token) : null;
  if (!user) return c.json({ error: "unauthorized" }, 401);
  c.set("user", user);
  await next();
};

function bearer(c: Context<AppContext>): string | null {
  const header = c.req.header("Authorization") ?? "";
  return header.startsWith("Bearer ") ? header.slice(7).trim() || null : null;
}

interface GoogleClaims {
  sub: string;
  email: string;
  name?: string;
}

/**
 * Reads the ID token returned directly by Google's token endpoint over TLS.
 * Google's docs allow skipping signature checks for tokens obtained this way;
 * audience, issuer, expiry and email verification are still enforced.
 */
export function googleClaims(idToken: string, clientId: string): GoogleClaims | null {
  try {
    const payload = JSON.parse(new TextDecoder().decode(fromBase64(idToken.split(".")[1] ?? "")));
    const issuerOk = payload.iss === "accounts.google.com" || payload.iss === "https://accounts.google.com";
    if (!issuerOk || payload.aud !== clientId || payload.exp < nowSeconds()) return null;
    if (!payload.sub || !payload.email || payload.email_verified !== true) return null;
    return { sub: String(payload.sub), email: String(payload.email), name: payload.name ? String(payload.name) : undefined };
  } catch {
    return null;
  }
}

function page(c: Context<AppContext>, title: string, message: string, status: 200 | 400 | 502, appUrl?: string) {
  const escape = (s: string) => s.replace(/[&<>"]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[ch]!);
  const redirect = appUrl
    ? `<meta http-equiv="refresh" content="0;url=${escape(appUrl)}"><p><a href="${escape(appUrl)}">Open Hear Agent</a></p>`
    : "";
  return c.html(
    `<!doctype html><html><head><meta charset="utf-8"><title>${escape(title)} · Hear Agent</title>
<style>body{font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:90vh;color:#222}main{text-align:center}a{color:#6b4eff}</style>
</head><body><main><h1>${escape(title)}</h1><p>${escape(message)}</p>${redirect}</main></body></html>`,
    status,
  );
}
