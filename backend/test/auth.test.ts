import { afterEach, describe, expect, it } from "vitest";
import { nowSeconds, sha256Base64url } from "../src/crypto";
import { googleClaims } from "../src/auth";
import { call, fakeIdToken, mockFetch, signedInUser, testEnv } from "./helpers";

let restore = () => {};
afterEach(() => restore());

const verifier = "v".repeat(48);

async function startSignIn(appState = "appstate123") {
  const challenge = await sha256Base64url(verifier);
  const res = await call(`/auth/google/start?app_state=${appState}&code_challenge=${challenge}`);
  expect(res.status).toBe(302);
  return new URL(res.headers.get("Location")!);
}

describe("Google sign-in", () => {
  it("redirects to Google with our callback and a signed state", async () => {
    const google = await startSignIn();
    expect(google.origin + google.pathname).toBe("https://accounts.google.com/o/oauth2/v2/auth");
    expect(google.searchParams.get("client_id")).toBe(testEnv.GOOGLE_CLIENT_ID);
    expect(google.searchParams.get("redirect_uri")).toBe("https://api.hearagent.test/auth/google/callback");
    expect(google.searchParams.get("scope")).toBe("openid email profile");
    expect(google.searchParams.get("state")).toContain(".");
  });

  it("rejects malformed start requests", async () => {
    expect((await call("/auth/google/start?app_state=x&code_challenge=y")).status).toBe(400);
  });

  it("completes the full flow: callback, one-time code, PKCE exchange, account", async () => {
    const google = await startSignIn();
    const state = google.searchParams.get("state")!;
    const mock = mockFetch({
      "https://oauth2.googleapis.com/token": () =>
        Response.json({
          id_token: fakeIdToken({
            iss: "https://accounts.google.com",
            aud: testEnv.GOOGLE_CLIENT_ID,
            exp: nowSeconds() + 3600,
            sub: "google-123",
            email: "karthik@example.com",
            email_verified: true,
            name: "Karthik",
          }),
        }),
    });
    restore = mock.restore;

    const callback = await call(`/auth/google/callback?code=google-code&state=${encodeURIComponent(state)}`);
    expect(callback.status).toBe(200);
    const html = await callback.text();
    const appUrl = html.match(/url=(hearagent:\/\/auth\?[^"]+)"/)![1].replace(/&amp;/g, "&");
    const parsed = new URL(appUrl);
    expect(parsed.searchParams.get("state")).toBe("appstate123");
    const code = parsed.searchParams.get("code")!;

    const tokenExchange = new URLSearchParams(mock.calls[0].body);
    expect(tokenExchange.get("client_secret")).toBe("google-secret");
    expect(tokenExchange.get("redirect_uri")).toBe("https://api.hearagent.test/auth/google/callback");

    const wrong = await call("/auth/exchange", { method: "POST", body: JSON.stringify({ code, code_verifier: "w".repeat(48) }) });
    expect(wrong.status).toBe(400);

    // The code was consumed by the failed attempt; sign in again to get a fresh one.
    const google2 = await startSignIn();
    const callback2 = await call(`/auth/google/callback?code=c2&state=${encodeURIComponent(google2.searchParams.get("state")!)}`);
    const code2 = new URL((await callback2.text()).match(/url=(hearagent:\/\/auth\?[^"]+)"/)![1].replace(/&amp;/g, "&")).searchParams.get("code")!;
    const ok = await call("/auth/exchange", { method: "POST", body: JSON.stringify({ code: code2, code_verifier: verifier }) });
    expect(ok.status).toBe(200);
    const { token } = await ok.json<{ token: string }>();
    expect(token).toMatch(/^ha_/);

    const reused = await call("/auth/exchange", { method: "POST", body: JSON.stringify({ code: code2, code_verifier: verifier }) });
    expect(reused.status).toBe(400);

    const account = await call("/v1/account", { headers: { Authorization: `Bearer ${token}` } });
    expect(await account.json()).toEqual({ email: "karthik@example.com", name: "Karthik", subscription: null });
  });

  it("rejects a tampered state", async () => {
    const google = await startSignIn();
    const state = google.searchParams.get("state")!;
    const tampered = state.slice(0, -2) + (state.endsWith("A") ? "BB" : "AA");
    const res = await call(`/auth/google/callback?code=x&state=${encodeURIComponent(tampered)}`);
    expect(res.status).toBe(400);
  });

  it("validates ID token claims", () => {
    const base = { iss: "accounts.google.com", aud: "cid", exp: nowSeconds() + 60, sub: "1", email: "a@b.c", email_verified: true };
    expect(googleClaims(fakeIdToken(base), "cid")).toEqual({ sub: "1", email: "a@b.c", name: undefined });
    expect(googleClaims(fakeIdToken({ ...base, aud: "other" }), "cid")).toBeNull();
    expect(googleClaims(fakeIdToken({ ...base, email_verified: false }), "cid")).toBeNull();
    expect(googleClaims(fakeIdToken({ ...base, exp: nowSeconds() - 1 }), "cid")).toBeNull();
    expect(googleClaims(fakeIdToken({ ...base, iss: "evil.com" }), "cid")).toBeNull();
  });
});

describe("sessions", () => {
  it("requires a valid bearer token", async () => {
    expect((await call("/v1/account")).status).toBe(401);
    expect((await call("/v1/account", { headers: { Authorization: "Bearer ha_nope" } })).status).toBe(401);
  });

  it("sign-out revokes the token", async () => {
    const { auth } = await signedInUser();
    expect((await call("/v1/account", { headers: auth })).status).toBe(200);
    await call("/auth/sign-out", { method: "POST", headers: auth });
    expect((await call("/v1/account", { headers: auth })).status).toBe(401);
  });
});
