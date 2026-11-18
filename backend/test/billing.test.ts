import { afterEach, describe, expect, it } from "vitest";
import { verifyWebhook } from "../src/billing";
import { nowSeconds } from "../src/crypto";
import { call, giveSubscription, mockFetch, signedInUser, testEnv, webhookHeaders } from "./helpers";

let restore = () => {};
afterEach(() => restore());

function subscriptionEvent(type: string, userId: string, overrides: Record<string, unknown> = {}) {
  return JSON.stringify({
    business_id: "bus_1",
    type,
    timestamp: new Date().toISOString(),
    data: {
      payload_type: "Subscription",
      subscription_id: `sub_for_${userId}`,
      status: "active",
      product_id: "pdt_starter",
      previous_billing_date: "2026-11-17T00:00:00Z",
      next_billing_date: "2026-12-17T00:00:00Z",
      cancel_at_next_billing_date: false,
      customer: { customer_id: "cus_42", email: "x@example.com" },
      metadata: { user_id: userId },
      ...overrides,
    },
  });
}

async function sendWebhook(body: string, id?: string) {
  return call("/webhooks/dodo", { method: "POST", headers: await webhookHeaders(body, id), body });
}

async function subRow(userId: string) {
  return testEnv.DB.prepare("SELECT * FROM subscriptions WHERE user_id = ?1").bind(userId).first<Record<string, unknown>>();
}

describe("Dodo webhooks", () => {
  it("activation grants 150,000 credits; renewal refills them", async () => {
    const { user, auth } = await signedInUser();
    expect((await sendWebhook(subscriptionEvent("subscription.active", user.id))).status).toBe(200);
    let row = await subRow(user.id);
    expect(row).toMatchObject({ status: "active", plan_id: "starter", credits_total: 150000, credits_used: 0, dodo_customer_id: "cus_42" });
    expect(row!.period_end).toBe(Date.parse("2026-12-17T00:00:00Z") / 1000);

    await testEnv.DB.prepare("UPDATE subscriptions SET credits_used = 90000 WHERE user_id = ?1").bind(user.id).run();
    // A mid-period update must not refill credits.
    await sendWebhook(subscriptionEvent("subscription.updated", user.id));
    expect((await subRow(user.id))!.credits_used).toBe(90000);

    await sendWebhook(
      subscriptionEvent("subscription.renewed", user.id, {
        previous_billing_date: "2026-12-17T00:00:00Z",
        next_billing_date: "2027-01-17T00:00:00Z",
      }),
    );
    row = await subRow(user.id);
    expect(row).toMatchObject({ credits_used: 0, period_end: Date.parse("2027-01-17T00:00:00Z") / 1000 });

    const account = await (await call("/v1/account", { headers: auth })).json<{ subscription: Record<string, unknown> }>();
    expect(account.subscription).toMatchObject({ plan_name: "Pro", credits_remaining: 150000, status: "active" });
  });

  it("cancellation keeps access until the period ends; expiry removes it", async () => {
    const { user } = await signedInUser();
    const future = new Date((nowSeconds() + 10 * 86400) * 1000).toISOString();
    await sendWebhook(subscriptionEvent("subscription.active", user.id, { next_billing_date: future }));
    await sendWebhook(subscriptionEvent("subscription.cancelled", user.id, { status: "cancelled", next_billing_date: future }));
    expect((await subRow(user.id))!.status).toBe("cancelled");

    const { hasAccess, getSubscription } = await import("../src/db");
    expect(hasAccess(await getSubscription(testEnv.DB, user.id))).toBe(true);
    await sendWebhook(subscriptionEvent("subscription.expired", user.id, { status: "expired", next_billing_date: future }));
    expect(hasAccess(await getSubscription(testEnv.DB, user.id))).toBe(false);
  });

  it("matches users by email when metadata is missing", async () => {
    const { user } = await signedInUser("buyer@example.com");
    await sendWebhook(subscriptionEvent("subscription.active", user.id, { metadata: {}, customer: { customer_id: "cus_7", email: "buyer@example.com" } }));
    expect((await subRow(user.id))!.dodo_customer_id).toBe("cus_7");
  });

  it("rejects bad signatures and ignores duplicate deliveries", async () => {
    const { user } = await signedInUser();
    const body = subscriptionEvent("subscription.active", user.id);
    const headers = await webhookHeaders(body);
    const forged = await call("/webhooks/dodo", { method: "POST", headers: { ...headers, "webhook-signature": "v1,AAAA" }, body });
    expect(forged.status).toBe(401);

    const first = await call("/webhooks/dodo", { method: "POST", headers, body });
    const again = await call("/webhooks/dodo", { method: "POST", headers, body });
    expect(await first.json()).toEqual({ ok: true });
    expect(await again.json()).toEqual({ ok: true, duplicate: true });
  });

  it("rejects stale timestamps", async () => {
    const body = "{}";
    const h = await webhookHeaders(body, "msg_old", nowSeconds() - 3600);
    expect(await verifyWebhook(testEnv.DODO_WEBHOOK_SECRET, h["webhook-id"], h["webhook-timestamp"], body, h["webhook-signature"])).toBe(false);
  });
});

describe("checkout and portal", () => {
  it("creates a Dodo checkout tagged with the user id", async () => {
    const { user, auth } = await signedInUser();
    const mock = mockFetch({
      "https://test.dodopayments.com/checkouts": () => Response.json({ session_id: "cks_1", checkout_url: "https://test.checkout.dodopayments.com/session/cks_1" }),
    });
    restore = mock.restore;
    const res = await call("/v1/billing/checkout", { method: "POST", headers: auth });
    expect(await res.json()).toEqual({ url: "https://test.checkout.dodopayments.com/session/cks_1" });
    const sent = JSON.parse(mock.calls[0].body);
    expect(sent).toMatchObject({
      product_cart: [{ product_id: "pdt_starter", quantity: 1 }],
      metadata: { user_id: user.id },
      return_url: "https://api.hearagent.test/billing/return",
    });
    expect(mock.calls[0].headers.get("authorization")).toBe("Bearer dodo-test");
  });

  it("opens the customer portal for subscribers", async () => {
    const { user, auth } = await signedInUser();
    expect((await call("/v1/billing/portal", { method: "POST", headers: auth })).status).toBe(402);
    await giveSubscription(user.id);
    const mock = mockFetch({ "https://test.dodopayments.com/customers/cus_1/customer-portal/session": () => Response.json({ link: "https://portal.dodo/x" }) });
    restore = mock.restore;
    const res = await call("/v1/billing/portal", { method: "POST", headers: auth });
    expect(await res.json()).toEqual({ url: "https://portal.dodo/x" });
  });
});
