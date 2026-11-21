import type { Context, MiddlewareHandler } from "hono";
import type { AppContext } from "./env";

export function publicOrigin(c: Context<AppContext>): string {
  return c.env.PUBLIC_URL || new URL(c.req.url).origin;
}

/** Accepts a Supabase access token (the app signs in with Supabase Auth directly). */
export const requireUser: MiddlewareHandler<AppContext> = async (c, next) => {
  const token = bearer(c);
  const user = token ? await c.var.store.userForToken(token) : null;
  if (!user) return c.json({ error: "unauthorized" }, 401);
  c.set("user", user);
  await next();
};

function bearer(c: Context<AppContext>): string | null {
  const header = c.req.header("Authorization") ?? "";
  return header.startsWith("Bearer ") ? header.slice(7).trim() || null : null;
}
