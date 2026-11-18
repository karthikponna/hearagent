import { Hono } from "hono";
import { auth, requireUser } from "./auth";
import { billing, billingPublic } from "./billing";
import { creditsRemaining, getSubscription, hasAccess, isoOrNull } from "./db";
import type { AppContext } from "./env";
import { speak } from "./speak";

const app = new Hono<AppContext>();

app.get("/", (c) => c.json({ name: "hearagent-api", ok: true }));
app.route("/auth", auth);
app.route("/", billingPublic);

app.use("/v1/*", requireUser);

app.get("/v1/account", async (c) => {
  const user = c.get("user");
  const sub = await getSubscription(c.env.DB, user.id);
  return c.json({
    email: user.email,
    name: user.name,
    subscription: sub && {
      status: sub.status,
      active: hasAccess(sub),
      plan_name: sub.plan_name,
      credits_total: sub.credits_total,
      credits_used: sub.credits_used,
      credits_remaining: creditsRemaining(sub),
      period_end: isoOrNull(sub.period_end),
      cancel_at_period_end: sub.cancel_at_period_end === 1,
    },
  });
});

app.route("/v1/speak", speak);
app.route("/v1/billing", billing);

app.onError((err, c) => {
  console.log(JSON.stringify({ event: "unhandled_error", message: String(err) }));
  return c.json({ error: "internal_error" }, 500);
});

export default app;
