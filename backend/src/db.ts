import { nowSeconds, randomToken, sha256Hex } from "./crypto";
import type { User } from "./env";

const SESSION_TTL_SECONDS = 180 * 24 * 60 * 60;
/** Renewal webhooks can arrive a little after the billing date. */
const RENEWAL_GRACE_SECONDS = 3 * 24 * 60 * 60;

export interface SubscriptionRow {
  user_id: string;
  dodo_subscription_id: string | null;
  dodo_customer_id: string | null;
  plan_id: string;
  plan_name: string;
  status: string;
  period_start: number | null;
  period_end: number | null;
  cancel_at_period_end: number;
  credits_total: number;
  credits_used: number;
}

export interface PlanRow {
  id: string;
  name: string;
  price_cents: number;
  monthly_credits: number;
  dodo_product_id: string | null;
}

export async function upsertGoogleUser(db: D1Database, sub: string, email: string, name: string): Promise<User> {
  const row = await db
    .prepare(
      `INSERT INTO users (id, google_sub, email, name, created_at) VALUES (?1, ?2, ?3, ?4, ?5)
       ON CONFLICT(google_sub) DO UPDATE SET email = excluded.email, name = excluded.name
       RETURNING id, email, name`,
    )
    .bind(crypto.randomUUID(), sub, email, name, nowSeconds())
    .first<User>();
  return row!;
}

export async function createSession(db: D1Database, userId: string): Promise<string> {
  const token = `ha_${randomToken(32)}`;
  const now = nowSeconds();
  await db
    .prepare("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?1, ?2, ?3, ?4)")
    .bind(await sha256Hex(token), userId, now, now + SESSION_TTL_SECONDS)
    .run();
  return token;
}

export async function userForToken(db: D1Database, token: string): Promise<User | null> {
  return db
    .prepare(
      `SELECT u.id, u.email, u.name FROM sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token_hash = ?1 AND s.expires_at > ?2`,
    )
    .bind(await sha256Hex(token), nowSeconds())
    .first<User>();
}

export async function deleteSession(db: D1Database, token: string): Promise<void> {
  await db.prepare("DELETE FROM sessions WHERE token_hash = ?1").bind(await sha256Hex(token)).run();
}

export async function getSubscription(db: D1Database, userId: string): Promise<SubscriptionRow | null> {
  return db
    .prepare(
      `SELECT s.*, p.name AS plan_name FROM subscriptions s JOIN plans p ON p.id = s.plan_id WHERE s.user_id = ?1`,
    )
    .bind(userId)
    .first<SubscriptionRow>();
}

export function hasAccess(sub: SubscriptionRow | null, now = nowSeconds()): boolean {
  if (!sub) return false;
  const inPeriod = sub.period_end === null || now < sub.period_end;
  switch (sub.status) {
    case "active":
      return sub.period_end === null || now < sub.period_end + RENEWAL_GRACE_SECONDS;
    case "cancelled":
      // Cancelled mid-period: keep what they paid for until the period ends.
      return inPeriod;
    default:
      return false;
  }
}

export function creditsRemaining(sub: SubscriptionRow): number {
  return Math.max(0, sub.credits_total - sub.credits_used);
}

/** Atomically spends credits. Returns false if not enough remain. */
export async function spendCredits(db: D1Database, userId: string, amount: number): Promise<boolean> {
  const result = await db
    .prepare(
      `UPDATE subscriptions SET credits_used = credits_used + ?1, updated_at = ?3
       WHERE user_id = ?2 AND credits_used + ?1 <= credits_total`,
    )
    .bind(amount, userId, nowSeconds())
    .run();
  return result.meta.changes === 1;
}

export async function refundCredits(db: D1Database, userId: string, amount: number): Promise<void> {
  await db
    .prepare("UPDATE subscriptions SET credits_used = MAX(0, credits_used - ?1), updated_at = ?3 WHERE user_id = ?2")
    .bind(amount, userId, nowSeconds())
    .run();
}

export async function planForProduct(db: D1Database, productId: string, defaultProductId: string): Promise<PlanRow | null> {
  const byProduct = await db.prepare("SELECT * FROM plans WHERE dodo_product_id = ?1").bind(productId).first<PlanRow>();
  if (byProduct) return byProduct;
  if (defaultProductId && productId === defaultProductId) {
    return db.prepare("SELECT * FROM plans WHERE id = 'starter'").first<PlanRow>();
  }
  return null;
}

export function isoOrNull(seconds: number | null): string | null {
  return seconds === null ? null : new Date(seconds * 1000).toISOString();
}
