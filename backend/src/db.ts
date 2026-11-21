import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { AppEnv, User } from "./env";

/** Renewal webhooks can arrive a little after the billing date. */
const RENEWAL_GRACE_MS = 3 * 24 * 60 * 60 * 1000;

export interface Plan {
  id: string;
  name: string;
  billing_interval: "month" | "year" | "lifetime";
  price_cents: number;
  monthly_credits: number;
  dodo_product_id: string | null;
}

export interface Subscription {
  user_id: string;
  plan_id: string;
  status: string;
  dodo_subscription_id: string | null;
  dodo_payment_id: string | null;
  dodo_customer_id: string | null;
  current_period_start: string | null;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  credits_total: number;
  credits_used: number;
  credits_reset_at: string | null;
}

export type SubscriptionWrite = Omit<Subscription, "credits_used"> & { credits_used?: number };

export interface SpendResult {
  ok: boolean;
  credits_remaining: number;
  credits_total: number;
  credits_reset_at: string | null;
}

/** Everything the Worker reads or writes. Supabase in production, in memory in tests. */
export interface Store {
  /** Verifies a Supabase access token. */
  userForToken(token: string): Promise<User | null>;
  /** The user's subscription, after any monthly credit refill that is due. */
  subscription(userId: string): Promise<Subscription | null>;
  plan(id: string): Promise<Plan | null>;
  planForProduct(productId: string): Promise<Plan | null>;
  spendCredits(userId: string, amount: number): Promise<SpendResult>;
  refundCredits(userId: string, amount: number): Promise<void>;
  /** Records a webhook delivery; false if it was already seen. */
  recordWebhook(id: string, type: string): Promise<boolean>;
  webhookUser(userId: string | null, subscriptionId: string | null, email: string | null): Promise<string | null>;
  saveSubscription(row: SubscriptionWrite): Promise<void>;
}

export function hasAccess(sub: Subscription | null, now = Date.now()): boolean {
  if (!sub) return false;
  const end = sub.current_period_end ? Date.parse(sub.current_period_end) : null;
  switch (sub.status) {
    case "active":
      return end === null || now < end + RENEWAL_GRACE_MS;
    case "cancelled":
      // Cancelled mid-period: keep what they paid for until the period ends.
      return end === null || now < end;
    default:
      return false;
  }
}

export function creditsRemaining(sub: Pick<Subscription, "credits_total" | "credits_used">): number {
  return Math.max(0, sub.credits_total - sub.credits_used);
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function supabaseStore(env: AppEnv): Store {
  const db: SupabaseClient = createClient(env.SUPABASE_URL, env.SUPABASE_SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const fail = (what: string, error: { message: string } | null) => {
    if (error) throw new Error(`supabase ${what}: ${error.message}`);
  };

  return {
    async userForToken(token) {
      const { data, error } = await db.auth.getClaims(token);
      if (error || !data?.claims?.sub || data.claims.role !== "authenticated") return null;
      const c = data.claims as Record<string, unknown> & { sub: string };
      const meta = (c.user_metadata ?? {}) as Record<string, unknown>;
      return {
        id: c.sub,
        email: typeof c.email === "string" ? c.email : "",
        name: String(meta.full_name ?? meta.name ?? ""),
      };
    },

    async subscription(userId) {
      const { data, error } = await db.rpc("current_subscription", { p_user_id: userId });
      fail("current_subscription", error);
      return ((data as Subscription[] | null) ?? [])[0] ?? null;
    },

    async plan(id) {
      const { data, error } = await db.from("plans").select("*").eq("id", id).eq("active", true).maybeSingle();
      fail("plan", error);
      return data as Plan | null;
    },

    async planForProduct(productId) {
      const { data, error } = await db.from("plans").select("*").eq("dodo_product_id", productId).maybeSingle();
      fail("planForProduct", error);
      return data as Plan | null;
    },

    async spendCredits(userId, amount) {
      const { data, error } = await db.rpc("spend_credits", { p_user_id: userId, p_amount: amount });
      fail("spend_credits", error);
      return ((data as SpendResult[] | null) ?? [])[0] ?? { ok: false, credits_remaining: 0, credits_total: 0, credits_reset_at: null };
    },

    async refundCredits(userId, amount) {
      const { error } = await db.rpc("refund_credits", { p_user_id: userId, p_amount: amount });
      fail("refund_credits", error);
    },

    async recordWebhook(id, type) {
      const { data, error } = await db.from("webhook_events").upsert({ id, type }, { onConflict: "id", ignoreDuplicates: true }).select("id");
      fail("webhook_events", error);
      return (data ?? []).length > 0;
    },

    async webhookUser(userId, subscriptionId, email) {
      const { data, error } = await db.rpc("webhook_user", {
        p_user_id: userId && UUID_RE.test(userId) ? userId : null,
        p_subscription_id: subscriptionId,
        p_email: email,
      });
      fail("webhook_user", error);
      return (data as string | null) ?? null;
    },

    async saveSubscription(row) {
      const { error } = await db.from("subscriptions").upsert({ ...row, updated_at: new Date().toISOString() }, { onConflict: "user_id" });
      fail("saveSubscription", error);
    },
  };
}
