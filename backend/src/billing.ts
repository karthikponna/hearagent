import { Hono } from "hono";
import { fromBase64, base64, hmacSha256, nowSeconds, timingSafeEqual } from "./crypto";
import type { Plan, Store } from "./db";
import type { AppContext, AppEnv } from "./env";
import { publicOrigin } from "./auth";

const WEBHOOK_TOLERANCE_SECONDS = 5 * 60;
const MONTH_MS = 30 * 24 * 60 * 60 * 1000;

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

/** Body: { "plan": "monthly" | "yearly" | "lifetime" }. Defaults to monthly. */
billing.post("/checkout", async (c) => {
  const user = c.get("user");
  const body = await c.req.json<{ plan?: string }>().catch(() => ({}) as { plan?: string });
  const plan = await c.var.store.plan(body.plan || "monthly");
  if (!plan) return c.json({ error: "unknown_plan" }, 400);
  if (!plan.dodo_product_id) return c.json({ error: "plan_not_configured" }, 503);
  try {
    const session = await dodo(c.env, "/checkouts", {
      product_cart: [{ product_id: plan.dodo_product_id, quantity: 1 }],
      customer: { email: user.email, name: user.name || user.email },
      metadata: { user_id: user.id, plan_id: plan.id },
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
  const sub = await c.var.store.subscription(c.get("user").id);
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
  const title = ok ? "You're all set" : "Checkout finished";
  const appUrl = `${c.env.APP_URL_SCHEME}://billing?status=${encodeURIComponent(c.req.query("status") ?? "")}`;
  return c.html(
    `<!doctype html><html><head><meta charset="utf-8"><title>${title} · Hear Agent</title><meta http-equiv="refresh" content="0;url=${appUrl}">
<style>body{font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:90vh}main{text-align:center}a{color:#111}</style></head>
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
  const event = JSON.parse(raw) as { type: string; data: DodoSubscription & DodoPayment };
  if (!(await c.var.store.recordWebhook(id, event.type))) return c.json({ ok: true, duplicate: true });

  if (event.type.startsWith("subscription.")) {
    await applySubscriptionEvent(c.var.store, event.type, event.data);
  } else if (event.type === "payment.succeeded" && !event.data.subscription_id) {
    await applyLifetimePayment(c.var.store, event.data);
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

export interface DodoPayment {
  payment_id: string;
  subscription_id?: string | null;
  customer?: { customer_id?: string; email?: string };
  metadata?: Record<string, unknown>;
}

const meta = (m: Record<string, unknown> | undefined, key: string) => (typeof m?.[key] === "string" ? (m[key] as string) : null);

async function planFor(store: Store, productId: string | null, metadataPlan: string | null): Promise<Plan | null> {
  return (productId ? await store.planForProduct(productId) : null) ?? (metadataPlan ? await store.plan(metadataPlan) : null);
}

export async function applySubscriptionEvent(store: Store, type: string, s: DodoSubscription): Promise<void> {
  const userId = await store.webhookUser(meta(s.metadata, "user_id"), s.subscription_id, s.customer?.email ?? null);
  if (!userId) {
    console.log(JSON.stringify({ event: "webhook_unmatched", type, subscription: s.subscription_id }));
    return;
  }
  const plan = await planFor(store, s.product_id, meta(s.metadata, "plan_id"));
  if (!plan) {
    console.log(JSON.stringify({ event: "webhook_unknown_product", product: s.product_id }));
    return;
  }
  const existing = await store.subscription(userId);
  // A lifetime purchase outlives any subscription event for the same user.
  if (existing && existing.plan_id !== plan.id && existing.status === "active" && existing.current_period_end === null) return;
  // First activation, or a switch to another plan, starts a fresh credit month.
  const fresh = !existing || existing.plan_id !== plan.id;
  await store.saveSubscription({
    user_id: userId,
    plan_id: plan.id,
    status: type === "subscription.cancelled" ? "cancelled" : s.status,
    dodo_subscription_id: s.subscription_id,
    dodo_payment_id: existing?.dodo_payment_id ?? null,
    dodo_customer_id: s.customer?.customer_id ?? existing?.dodo_customer_id ?? null,
    current_period_start: s.previous_billing_date ?? existing?.current_period_start ?? null,
    current_period_end: s.next_billing_date ?? existing?.current_period_end ?? null,
    cancel_at_period_end: !!s.cancel_at_next_billing_date,
    credits_total: plan.monthly_credits,
    credits_reset_at: fresh ? new Date(Date.now() + MONTH_MS).toISOString() : existing!.credits_reset_at,
    ...(fresh ? { credits_used: 0 } : {}),
  });
  console.log(JSON.stringify({ event: "subscription_updated", type, status: s.status, user: userId, plan: plan.id }));
}

/** One-time payments are only used for the lifetime plan. */
export async function applyLifetimePayment(store: Store, p: DodoPayment): Promise<void> {
  const plan = await planFor(store, null, meta(p.metadata, "plan_id"));
  if (plan?.billing_interval !== "lifetime") return;
  const userId = await store.webhookUser(meta(p.metadata, "user_id"), null, p.customer?.email ?? null);
  if (!userId) {
    console.log(JSON.stringify({ event: "webhook_unmatched", type: "payment.succeeded", payment: p.payment_id }));
    return;
  }
  const existing = await store.subscription(userId);
  await store.saveSubscription({
    user_id: userId,
    plan_id: plan.id,
    status: "active",
    dodo_subscription_id: existing?.dodo_subscription_id ?? null,
    dodo_payment_id: p.payment_id,
    dodo_customer_id: p.customer?.customer_id ?? existing?.dodo_customer_id ?? null,
    current_period_start: new Date().toISOString(),
    current_period_end: null,
    cancel_at_period_end: false,
    credits_total: plan.monthly_credits,
    credits_used: 0,
    credits_reset_at: new Date(Date.now() + MONTH_MS).toISOString(),
  });
  console.log(JSON.stringify({ event: "lifetime_purchased", user: userId }));
}
