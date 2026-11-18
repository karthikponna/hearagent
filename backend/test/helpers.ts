import { env } from "cloudflare:workers";
import app from "../src/index";
import { base64, base64url, hmacSha256, nowSeconds } from "../src/crypto";
import { createSession, upsertGoogleUser } from "../src/db";
import type { AppEnv } from "../src/env";

export const testEnv = env as unknown as AppEnv;

export function call(path: string, init: RequestInit = {}) {
  return app.request(`https://api.hearagent.test${path}`, init, testEnv);
}

export async function signedInUser(email = `dev${crypto.randomUUID().slice(0, 8)}@example.com`) {
  const user = await upsertGoogleUser(testEnv.DB, `google-${email}`, email, "Dev");
  const token = await createSession(testEnv.DB, user.id);
  return { user, token, auth: { Authorization: `Bearer ${token}` } };
}

export async function giveSubscription(userId: string, opts: { credits?: number; used?: number; status?: string; periodEnd?: number } = {}) {
  const now = nowSeconds();
  await testEnv.DB.prepare(
    `INSERT OR REPLACE INTO subscriptions (user_id, dodo_subscription_id, dodo_customer_id, plan_id, status, period_start, period_end,
       cancel_at_period_end, credits_total, credits_used, updated_at)
     VALUES (?1, ?2, 'cus_1', 'starter', ?3, ?4, ?5, 0, ?6, ?7, ?4)`,
  )
    .bind(userId, `sub_${userId}`, opts.status ?? "active", now, opts.periodEnd ?? now + 30 * 86400, opts.credits ?? 150000, opts.used ?? 0)
    .run();
}

export async function webhookHeaders(body: string, id = `msg_${crypto.randomUUID()}`, timestamp = nowSeconds()) {
  const key = Uint8Array.from(atob(testEnv.DODO_WEBHOOK_SECRET.slice(6)), (c) => c.charCodeAt(0));
  const sig = base64(await hmacSha256(key, `${id}.${timestamp}.${body}`));
  return { "webhook-id": id, "webhook-timestamp": String(timestamp), "webhook-signature": `v1,${sig}`, "Content-Type": "application/json" };
}

export function fakeIdToken(claims: Record<string, unknown>) {
  const enc = (o: object) => base64url(new TextEncoder().encode(JSON.stringify(o)));
  return `${enc({ alg: "RS256" })}.${enc(claims)}.signature`;
}

/** Routes outbound fetches by URL prefix; anything unmatched fails the test. */
export function mockFetch(routes: Record<string, (req: Request) => Response | Promise<Response>>) {
  const calls: { url: string; body: string; headers: Headers }[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    const body = await req.clone().text();
    calls.push({ url: req.url, body, headers: req.headers });
    const match = Object.keys(routes).find((prefix) => req.url.startsWith(prefix));
    if (!match) throw new Error(`unexpected fetch ${req.url}`);
    return routes[match](req);
  }) as typeof fetch;
  return { calls, restore: () => (globalThis.fetch = original) };
}
