import { env } from "cloudflare:workers";
import { createApp } from "../src/index";
import { base64, hmacSha256, nowSeconds } from "../src/crypto";
import type { Plan, Store, Subscription } from "../src/db";
import type { AppEnv, User } from "../src/env";

export const testEnv = env as unknown as AppEnv;

const MONTH_MS = 30 * 24 * 60 * 60 * 1000;

/** The Supabase schema's behaviour, in memory: plans, subscriptions with monthly refills, tokens and webhook ids. */
export class MemoryStore implements Store {
  users = new Map<string, User>();
  tokens = new Map<string, string>();
  subs = new Map<string, Subscription>();
  webhooks = new Set<string>();
  plans: Plan[] = [
    { id: "monthly", name: "Monthly", billing_interval: "month", price_cents: 1900, monthly_credits: 150000, dodo_product_id: "pdt_monthly" },
    { id: "yearly", name: "Yearly", billing_interval: "year", price_cents: 14900, monthly_credits: 150000, dodo_product_id: "pdt_yearly" },
    { id: "lifetime", name: "Lifetime", billing_interval: "lifetime", price_cents: 29900, monthly_credits: 150000, dodo_product_id: "pdt_lifetime" },
  ];

  async userForToken(token: string) {
    const id = this.tokens.get(token);
    return id ? (this.users.get(id) ?? null) : null;
  }
  async subscription(userId: string) {
    const s = this.subs.get(userId);
    if (!s) return null;
    if (s.credits_reset_at && Date.parse(s.credits_reset_at) <= Date.now()) {
      let next = Date.parse(s.credits_reset_at);
      while (next <= Date.now()) next += MONTH_MS;
      s.credits_used = 0;
      s.credits_reset_at = new Date(next).toISOString();
    }
    return { ...s };
  }
  async plan(id: string) {
    return this.plans.find((p) => p.id === id) ?? null;
  }
  async planForProduct(productId: string) {
    return this.plans.find((p) => p.dodo_product_id === productId) ?? null;
  }
  async spendCredits(userId: string, amount: number) {
    const s = await this.subscription(userId);
    if (!s) return { ok: false, credits_remaining: 0, credits_total: 0, credits_reset_at: null };
    if (s.credits_used + amount > s.credits_total) {
      return { ok: false, credits_remaining: s.credits_total - s.credits_used, credits_total: s.credits_total, credits_reset_at: s.credits_reset_at };
    }
    this.subs.get(userId)!.credits_used += amount;
    return { ok: true, credits_remaining: s.credits_total - s.credits_used - amount, credits_total: s.credits_total, credits_reset_at: s.credits_reset_at };
  }
  async refundCredits(userId: string, amount: number) {
    const s = this.subs.get(userId);
    if (s) s.credits_used = Math.max(0, s.credits_used - amount);
  }
  async recordWebhook(id: string) {
    if (this.webhooks.has(id)) return false;
    this.webhooks.add(id);
    return true;
  }
  async webhookUser(userId: string | null, subscriptionId: string | null, email: string | null) {
    if (userId && this.users.has(userId)) return userId;
    for (const s of this.subs.values()) if (subscriptionId && s.dodo_subscription_id === subscriptionId) return s.user_id;
    for (const u of this.users.values()) if (email && u.email.toLowerCase() === email.toLowerCase()) return u.id;
    return null;
  }
  async saveSubscription(row: Parameters<Store["saveSubscription"]>[0]) {
    const existing = this.subs.get(row.user_id);
    this.subs.set(row.user_id, { ...row, credits_used: row.credits_used ?? existing?.credits_used ?? 0 });
  }
}

export function harness() {
  const store = new MemoryStore();
  const app = createApp(() => store);
  const call = (path: string, init: RequestInit = {}) => app.request(`https://api.hearagent.test${path}`, init, testEnv);

  function signedInUser(email = `dev${crypto.randomUUID().slice(0, 8)}@example.com`) {
    const user = { id: crypto.randomUUID(), email, name: "Dev" };
    const token = `jwt_${crypto.randomUUID()}`;
    store.users.set(user.id, user);
    store.tokens.set(token, user.id);
    return { user, token, auth: { Authorization: `Bearer ${token}` } };
  }

  function giveSubscription(userId: string, opts: { credits?: number; used?: number; status?: string; periodEnd?: number; plan?: string } = {}) {
    const now = Date.now();
    store.subs.set(userId, {
      user_id: userId,
      plan_id: opts.plan ?? "monthly",
      status: opts.status ?? "active",
      dodo_subscription_id: `sub_${userId}`,
      dodo_payment_id: null,
      dodo_customer_id: "cus_1",
      current_period_start: new Date(now).toISOString(),
      current_period_end: new Date(opts.periodEnd ?? now + MONTH_MS).toISOString(),
      cancel_at_period_end: false,
      credits_total: opts.credits ?? 150000,
      credits_used: opts.used ?? 0,
      credits_reset_at: new Date(now + MONTH_MS).toISOString(),
    });
  }

  return { store, call, signedInUser, giveSubscription };
}

export async function webhookHeaders(body: string, id = `msg_${crypto.randomUUID()}`, timestamp = nowSeconds()) {
  const key = Uint8Array.from(atob(testEnv.DODO_WEBHOOK_SECRET.slice(6)), (c) => c.charCodeAt(0));
  const sig = base64(await hmacSha256(key, `${id}.${timestamp}.${body}`));
  return { "webhook-id": id, "webhook-timestamp": String(timestamp), "webhook-signature": `v1,${sig}`, "Content-Type": "application/json" };
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
