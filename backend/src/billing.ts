import { Hono } from "hono";
import { fromBase64, base64, hmacSha256, nowSeconds, timingSafeEqual } from "./crypto";
import { getSubscription, planForProduct } from "./db";
import type { AppContext, AppEnv } from "./env";
import { publicOrigin } from "./auth";

const WEBHOOK_TOLERANCE_SECONDS = 5 * 60;

function dodoBase(env: AppEnv): string {
  return env.DODO_ENVIRONMENT === "live_mode" ? "https://live.dodopayments.com" : "https://test.dodopayments.com";
}

async function dodo(env: AppEnv, path: string, body: unknown): Promise<Record<string, unknown>> {
  const res = await fetch(`${dodoBase(env)}${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.DODO_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`dodo ${path} ${res.status}`);
  return res.json();
}

/** Authenticated routes under /v1/billing. */
export const billing = new Hono<AppContext>();

billing.post("/checkout", async (c) => {
  const user = c.get("user");
  try {
    const session = await dodo(c.env, "/checkouts", {
      product_cart: [{ product_id: c.env.DODO_PRODUCT_ID, quantity: 1 }],
      customer: { email: user.email, name: user.name || user.email },
      metadata: { user_id: user.id },
      return_url: `${publicOrigin(c)}/billing/return`,
    });
    const url = session.checkout_url;
    if (typeof url !== "string") throw new Error("no checkout_url");
    return c.json({ url });
  } catch (e) {
    console.log(JSON.stringify({ event: "checkout_error", message: String(e) }));
    return c.json({ error: "checkout_failed" }, 502);
  }
});

billing.post("/portal", async (c) => {
  const sub = await getSubscription(c.env.DB, c.get("user").id);
  if (!sub?.dodo_customer_id) return c.json({ error: "no_subscription" }, 402);
  try {
    const session = await dodo(c.env, `/customers/${sub.dodo_customer_id}/customer-portal/session`, {});
    const url = session.link ?? session.url;
    if (typeof url !== "string") throw new Error("no portal link");
    return c.json({ url });
  } catch (e) {
    console.log(JSON.stringify({ event: "portal_error", message: String(e) }));
    return c.json({ error: "portal_failed" }, 502);
  }
});

/** Public routes: the checkout return page and Dodo's webhook. */
export const billingPublic = new Hono<AppContext>();

billingPublic.get("/billing/return", (c) => {
  const ok = c.req.query("status") === "active" || c.req.query("status") === "succeeded";
  const title = ok ? "You're subscribed" : "Checkout finished";
  const appUrl = `${c.env.APP_URL_SCHEME}://billing?status=${encodeURIComponent(c.req.query("status") ?? "")}`;
  return c.html(
    `<!doctype html><html><head><meta charset="utf-8"><title>${title} · Hear Agent</title><meta http-equiv="refresh" content="0;url=${appUrl}">
<style>body{font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:90vh}main{text-align:center}a{color:#6b4eff}</style></head>
<body><main><h1>${title}</h1><p>You can go back to Hear Agent now.</p><p><a href="${appUrl}">Open Hear Agent</a></p></main></body></html>`,
  );
});

billingPublic.post("/webhooks/dodo", async (c) => {
  const raw = await c.req.text();
  const id = c.req.header("webhook-id") ?? "";
  const timestamp = c.req.header("webhook-timestamp") ?? "";
  const signature = c.req.header("webhook-signature") ?? "";
  if (!(await verifyWebhook(c.env.DODO_WEBHOOK_SECRET, id, timestamp, raw, signature))) {
    return c.json({ error: "invalid_signature" }, 401);
  }
  const fresh = await c.env.DB.prepare("INSERT OR IGNORE INTO webhook_events (id, type, received_at) VALUES (?1, '', ?2)")
    .bind(id, nowSeconds())
    .run();
  if (fresh.meta.changes === 0) return c.json({ ok: true, duplicate: true });

  const event = JSON.parse(raw) as { type: string; data: DodoSubscription };
  await c.env.DB.prepare("UPDATE webhook_events SET type = ?1 WHERE id = ?2").bind(event.type, id).run();
  if (event.type.startsWith("subscription.")) {
    await applySubscriptionEvent(c.env, event.type, event.data);
  }
  return c.json({ ok: true });
});

/** Standard Webhooks signature: base64(HMAC-SHA256(secret, "id.timestamp.body")), header "v1,<sig> ...". */
export async function verifyWebhook(secret: string, id: string, timestamp: string, body: string, header: string): Promise<boolean> {
  if (!secret || !id || !timestamp || !header) return false;
  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(nowSeconds() - ts) > WEBHOOK_TOLERANCE_SECONDS) return false;
  const key = fromBase64(secret.startsWith("whsec_") ? secret.slice(6) : secret);
  const expected = base64(await hmacSha256(key, `${id}.${timestamp}.${body}`));
  return header.split(" ").some((part) => {
    const [version, sig] = part.split(",");
    return version === "v1" && !!sig && timingSafeEqual(sig, expected);
  });
}

export interface DodoSubscription {
  subscription_id: string;
  status: string;
  product_id: string;
  next_billing_date?: string;
  previous_billing_date?: string;
  cancel_at_next_billing_date?: boolean;
  customer?: { customer_id?: string; email?: string };
  metadata?: Record<string, unknown>;
}

const toSeconds = (iso?: string) => (iso ? Math.floor(Date.parse(iso) / 1000) : null);

export async function applySubscriptionEvent(env: AppEnv, type: string, s: DodoSubscription): Promise<void> {
  const db = env.DB;
  const userId = await resolveUser(db, s);
  if (!userId) {
    console.log(JSON.stringify({ event: "webhook_unmatched", type, subscription: s.subscription_id }));
    return;
  }
  const plan = await planForProduct(db, s.product_id, env.DODO_PRODUCT_ID);
  if (!plan) {
    console.log(JSON.stringify({ event: "webhook_unknown_product", product: s.product_id }));
    return;
  }
  const periodStart = toSeconds(s.previous_billing_date);
  const periodEnd = toSeconds(s.next_billing_date);
  const existing = await db.prepare("SELECT plan_id, period_start FROM subscriptions WHERE user_id = ?1")
    .bind(userId)
    .first<{ plan_id: string; period_start: number | null }>();
  // A new billing period (first activation or renewal) refills the monthly credits.
  const newPeriod = !existing || (periodStart !== null && existing.period_start !== periodStart);
  const status = type === "subscription.cancelled" ? "cancelled" : s.status;

  await db
    .prepare(
      `INSERT INTO subscriptions (user_id, dodo_subscription_id, dodo_customer_id, plan_id, status, period_start, period_end,
         cancel_at_period_end, credits_total, credits_used, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 0, ?10)
       ON CONFLICT(user_id) DO UPDATE SET
         dodo_subscription_id = excluded.dodo_subscription_id,
         dodo_customer_id = COALESCE(excluded.dodo_customer_id, subscriptions.dodo_customer_id),
         plan_id = excluded.plan_id,
         status = excluded.status,
         period_start = COALESCE(excluded.period_start, subscriptions.period_start),
         period_end = COALESCE(excluded.period_end, subscriptions.period_end),
         cancel_at_period_end = excluded.cancel_at_period_end,
         credits_total = excluded.credits_total,
         credits_used = CASE WHEN ?11 THEN 0 ELSE subscriptions.credits_used END,
         updated_at = excluded.updated_at`,
    )
    .bind(
      userId,
      s.subscription_id,
      s.customer?.customer_id ?? null,
      plan.id,
      status,
      periodStart,
      periodEnd,
      s.cancel_at_next_billing_date ? 1 : 0,
      plan.monthly_credits,
      nowSeconds(),
      newPeriod ? 1 : 0,
    )
    .run();
  console.log(JSON.stringify({ event: "subscription_updated", type, status, user: userId, new_period: newPeriod }));
}

async function resolveUser(db: D1Database, s: DodoSubscription): Promise<string | null> {
  const fromMetadata = typeof s.metadata?.user_id === "string" ? s.metadata.user_id : null;
  if (fromMetadata) {
    const u = await db.prepare("SELECT id FROM users WHERE id = ?1").bind(fromMetadata).first<{ id: string }>();
    if (u) return u.id;
  }
  const bySub = await db.prepare("SELECT user_id FROM subscriptions WHERE dodo_subscription_id = ?1")
    .bind(s.subscription_id)
    .first<{ user_id: string }>();
  if (bySub) return bySub.user_id;
  if (s.customer?.email) {
    const byEmail = await db.prepare("SELECT id FROM users WHERE email = ?1 ORDER BY created_at LIMIT 1")
      .bind(s.customer.email)
      .first<{ id: string }>();
    if (byEmail) return byEmail.id;
  }
  return null;
}
