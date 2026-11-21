import { afterEach, describe, expect, it } from "vitest";
import { verifyWebhook } from "../src/billing";
import { nowSeconds } from "../src/crypto";
import { hasAccess } from "../src/db";
import { harness, mockFetch, testEnv, webhookHeaders } from "./helpers";

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
      product_id: "pdt_monthly",
      previous_billing_date: "2026-11-17T00:00:00Z",
      next_billing_date: "2026-12-17T00:00:00Z",
      cancel_at_next_billing_date: false,
      customer: { customer_id: "cus_42", email: "x@example.com" },
      metadata: { user_id: userId, plan_id: "monthly" },
      ...overrides,
    },
  });
}

function setup() {
  const h = harness();
  const sendWebhook = async (body: string, id?: string) =>
    h.call("/webhooks/dodo", { method: "POST", headers: await webhookHeaders(body, id), body });
  return { ...h, sendWebhook };
}

describe("Dodo webhooks", () => {
  it("activation grants 150,000 credits; updates and renewals keep the credit month", async () => {
    const { store, call, signedInUser, sendWebhook } = setup();
    const { user, auth } = signedInUser();
    expect((await sendWebhook(subscriptionEvent("subscription.active", user.id))).status).toBe(200);
    let row = store.subs.get(user.id)!;
    expect(row).toMatchObject({ status: "active", plan_id: "monthly", credits_total: 150000, credits_used: 0, dodo_customer_id: "cus_42" });
    expect(row.current_period_end).toBe("2026-12-17T00:00:00Z");

    row.credits_used = 90000;
    await sendWebhook(subscriptionEvent("subscription.updated", user.id));
    expect(store.subs.get(user.id)!.credits_used).toBe(90000);

    await sendWebhook(subscriptionEvent("subscription.renewed", user.id, { previous_billing_date: "2026-12-17T00:00:00Z", next_billing_date: "2027-01-17T00:00:00Z" }));
    row = store.subs.get(user.id)!;
    expect(row.current_period_end).toBe("2027-01-17T00:00:00Z");

    const account = await (await call("/v1/account", { headers: auth })).json<{ subscription: Record<string, unknown> }>();
    expect(account.subscription).toMatchObject({ plan_name: "Monthly", status: "active" });
  });

  it("switching plans starts a fresh credit month", async () => {
    const { store, signedInUser, sendWebhook } = setup();
    const { user } = signedInUser();
    await sendWebhook(subscriptionEvent("subscription.active", user.id));
    store.subs.get(user.id)!.credits_used = 5000;
    await sendWebhook(subscriptionEvent("subscription.plan_changed", user.id, { product_id: "pdt_yearly" }));
    expect(store.subs.get(user.id)).toMatchObject({ plan_id: "yearly", credits_used: 0 });
  });

  it("cancellation keeps access until the period ends; expiry removes it", async () => {
    const { store, signedInUser, sendWebhook } = setup();
    const { user } = signedInUser();
    const future = new Date((nowSeconds() + 10 * 86400) * 1000).toISOString();
    await sendWebhook(subscriptionEvent("subscription.active", user.id, { next_billing_date: future }));
    await sendWebhook(subscriptionEvent("subscription.cancelled", user.id, { status: "cancelled", next_billing_date: future }));
    expect(store.subs.get(user.id)!.status).toBe("cancelled");
    expect(hasAccess(await store.subscription(user.id))).toBe(true);
    await sendWebhook(subscriptionEvent("subscription.expired", user.id, { status: "expired", next_billing_date: future }));
    expect(hasAccess(await store.subscription(user.id))).toBe(false);
  });

  it("a lifetime payment grants access with no end date", async () => {
    const { store, signedInUser, sendWebhook } = setup();
    const { user } = signedInUser();
    const body = JSON.stringify({
      type: "payment.succeeded",
      data: { payment_id: "pay_1", subscription_id: null, customer: { customer_id: "cus_9" }, metadata: { user_id: user.id, plan_id: "lifetime" } },
    });
    await sendWebhook(body);
    const row = store.subs.get(user.id)!;
    expect(row).toMatchObject({ plan_id: "lifetime", status: "active", current_period_end: null, dodo_payment_id: "pay_1", credits_total: 150000 });
    expect(hasAccess(row)).toBe(true);

    // A stray event from an old subscription can't downgrade a lifetime buyer.
    await sendWebhook(subscriptionEvent("subscription.expired", user.id, { status: "expired" }));
    expect(store.subs.get(user.id)!.plan_id).toBe("lifetime");
  });

  it("matches users by email when metadata is missing", async () => {
    const { store, signedInUser, sendWebhook } = setup();
    const { user } = signedInUser("buyer@example.com");
    await sendWebhook(subscriptionEvent("subscription.active", user.id, { metadata: {}, customer: { customer_id: "cus_7", email: "Buyer@example.com" } }));
    expect(store.subs.get(user.id)!.dodo_customer_id).toBe("cus_7");
  });

  it("rejects bad signatures and ignores duplicate deliveries", async () => {
    const { call, signedInUser } = setup();
    const { user } = signedInUser();
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
  it("creates a Dodo checkout for the chosen plan, tagged with the user", async () => {
    const { call, signedInUser } = setup();
    const { user, auth } = signedInUser();
    const mock = mockFetch({
      "https://test.dodopayments.com/checkouts": () => Response.json({ session_id: "cks_1", checkout_url: "https://test.checkout.dodopayments.com/session/cks_1" }),
    });
    restore = mock.restore;
    const res = await call("/v1/billing/checkout", { method: "POST", headers: { ...auth, "Content-Type": "application/json" }, body: JSON.stringify({ plan: "yearly" }) });
    expect(await res.json()).toEqual({ url: "https://test.checkout.dodopayments.com/session/cks_1" });
    expect(JSON.parse(mock.calls[0].body)).toMatchObject({
      product_cart: [{ product_id: "pdt_yearly", quantity: 1 }],
      metadata: { user_id: user.id, plan_id: "yearly" },
      return_url: "https://api.hearagent.test/billing/return",
    });
    expect(mock.calls[0].headers.get("authorization")).toBe("Bearer dodo-test");
  });

  it("rejects unknown plans and plans without a Dodo product", async () => {
    const { store, call, signedInUser } = setup();
    const { auth } = signedInUser();
    const post = (plan: string) => call("/v1/billing/checkout", { method: "POST", headers: auth, body: JSON.stringify({ plan }) });
    expect((await post("weekly")).status).toBe(400);
    store.plans[2].dodo_product_id = null;
    expect((await post("lifetime")).status).toBe(503);
  });

  it("opens the customer portal for subscribers", async () => {
    const { call, signedInUser, giveSubscription } = setup();
    const { user, auth } = signedInUser();
    expect((await call("/v1/billing/portal", { method: "POST", headers: auth })).status).toBe(402);
    giveSubscription(user.id);
    const mock = mockFetch({ "https://test.dodopayments.com/customers/cus_1/customer-portal/session": () => Response.json({ link: "https://portal.dodo/x" }) });
    restore = mock.restore;
    const res = await call("/v1/billing/portal", { method: "POST", headers: auth });
    expect(await res.json()).toEqual({ url: "https://portal.dodo/x" });
  });
});
