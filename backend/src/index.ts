import { Hono } from "hono";
import { requireUser } from "./auth";
import { billing, billingPublic } from "./billing";
import { creditsRemaining, hasAccess, supabaseStore, type Store } from "./db";
import type { AppContext, AppEnv } from "./env";
import { releases } from "./releases";
import { speak } from "./speak";

export function createApp(storeFor: (env: AppEnv) => Store) {
  const app = new Hono<AppContext>();

  app.use("*", async (c, next) => {
    c.set("store", storeFor(c.env));
    await next();
  });

  app.get("/", (c) => c.json({ name: "hearagent-api", ok: true }));
  app.route("/", billingPublic);
  app.route("/releases", releases);

  app.use("/v1/*", requireUser);

  app.get("/v1/account", async (c) => {
    const user = c.get("user");
    const sub = await c.var.store.subscription(user.id);
    const plan = sub ? await c.var.store.plan(sub.plan_id) : null;
    return c.json({
      email: user.email,
      name: user.name,
      subscription: sub && {
        status: sub.status,
        active: hasAccess(sub),
        plan_id: sub.plan_id,
        plan_name: plan?.name ?? sub.plan_id,
        credits_total: sub.credits_total,
        credits_used: sub.credits_used,
        credits_remaining: creditsRemaining(sub),
        // When credits next refill; null for none scheduled.
        period_end: sub.credits_reset_at,
        renews_at: sub.current_period_end,
        cancel_at_period_end: sub.cancel_at_period_end,
      },
    });
  });

  app.route("/v1/speak", speak);
  app.route("/v1/billing", billing);

  app.onError((err, c) => {
    console.log(JSON.stringify({ event: "unhandled_error", message: String(err) }));
    return c.json({ error: "internal_error" }, 500);
  });

  return app;
}

// One client per isolate, so the Supabase signing keys stay cached between requests.
let shared: { key: string; store: Store } | null = null;

export default createApp((env) => {
  const key = `${env.SUPABASE_URL}|${env.SUPABASE_SECRET_KEY}`;
  if (shared?.key !== key) shared = { key, store: supabaseStore(env) };
  return shared.store;
});
