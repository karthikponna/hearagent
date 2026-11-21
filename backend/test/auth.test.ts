import { describe, expect, it } from "vitest";
import { harness } from "./helpers";

describe("Supabase access tokens", () => {
  it("requires a valid bearer token", async () => {
    const { call } = harness();
    expect((await call("/v1/account")).status).toBe(401);
    expect((await call("/v1/account", { headers: { Authorization: "Bearer nope" } })).status).toBe(401);
  });

  it("returns the account for a signed-in user, with or without a plan", async () => {
    const { call, signedInUser, giveSubscription } = harness();
    const { user, auth } = signedInUser("ada@example.com");
    let account = await (await call("/v1/account", { headers: auth })).json<Record<string, unknown>>();
    expect(account).toEqual({ email: "ada@example.com", name: "Dev", subscription: null });

    giveSubscription(user.id, { plan: "yearly", used: 1000 });
    account = await (await call("/v1/account", { headers: auth })).json<Record<string, unknown>>();
    expect(account.subscription).toMatchObject({ active: true, plan_id: "yearly", plan_name: "Yearly", credits_remaining: 149000 });
  });

  it("refills credits once a month has passed", async () => {
    const { call, store, signedInUser, giveSubscription } = harness();
    const { user, auth } = signedInUser();
    giveSubscription(user.id, { used: 150000 });
    store.subs.get(user.id)!.credits_reset_at = new Date(Date.now() - 1000).toISOString();
    const account = await (await call("/v1/account", { headers: auth })).json<{ subscription: Record<string, unknown> }>();
    expect(account.subscription.credits_remaining).toBe(150000);
    expect(Date.parse(account.subscription.period_end as string)).toBeGreaterThan(Date.now());
  });
});
