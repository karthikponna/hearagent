import { afterEach, describe, expect, it } from "vitest";
import { capSpoken, clean, fallbackLine, parseRequest } from "../src/speak";
import { call, giveSubscription, mockFetch, signedInUser, testEnv } from "./helpers";

let restore = () => {};
afterEach(() => restore());

const summaryBody = {
  kind: "summary",
  agent: "Claude",
  name: "tool timeout mcp",
  final_message: "I added a timeout to the MCP client and all tests pass.",
  digest: { prompt: "add a timeout", files_changed: ["client.ts"], commands: ["npm test"], failures: ["npm test: Exit code 1"], tool_calls: 5 },
};

const mp3 = new Uint8Array([0x49, 0x44, 0x33, 1, 2, 3]);

function providers(text = "Hey, tool timeout mcp just finished adding the timeout, and the tests pass after one fix.") {
  return mockFetch({
    "https://api.openai.com/v1/responses": () =>
      Response.json({
        id: "resp_1",
        object: "response",
        status: "completed",
        output: [{ type: "message", role: "assistant", content: [{ type: "output_text", text, annotations: [] }] }],
      }),
    "https://api.elevenlabs.io/v1/text-to-speech/": () => new Response(mp3, { headers: { "Content-Type": "audio/mpeg" } }),
  });
}

async function post(body: unknown, headers: Record<string, string>) {
  return call("/v1/speak", { method: "POST", headers: { ...headers, "Content-Type": "application/json" }, body: JSON.stringify(body) });
}

describe("/v1/speak", () => {
  it("writes a summary with GPT-5 mini, voices it with George, and spends credits", async () => {
    const { user, auth } = await signedInUser();
    await giveSubscription(user.id, { credits: 150000 });
    const mock = providers();
    restore = mock.restore;

    const res = await post(summaryBody, auth);
    expect(res.status).toBe(200);
    const json = await res.json<Record<string, unknown>>();
    const text = "Hey, tool timeout mcp just finished adding the timeout, and the tests pass after one fix.";
    expect(json.text).toBe(text);
    expect(json.audio_format).toBe("mp3");
    expect(Uint8Array.from(atob(json.audio_base64 as string), (c) => c.charCodeAt(0))).toEqual(mp3);
    expect(json.credits_remaining).toBe(150000 - text.length);

    const openai = JSON.parse(mock.calls[0].body);
    expect(openai.model).toBe("gpt-5-mini");
    expect(openai.reasoning).toEqual({ effort: "minimal" });
    expect(openai.store).toBe(false);
    expect(JSON.parse(openai.input)).toMatchObject({ session_name: "tool timeout mcp", failures_during_run: ["npm test: Exit code 1"] });
    expect(mock.calls[0].headers.get("authorization")).toBe("Bearer sk-test");

    const tts = mock.calls[1];
    expect(tts.url).toContain("/v1/text-to-speech/JBFqnCBsd6RMkjVDRZzb");
    expect(tts.headers.get("xi-api-key")).toBe("el-test");
    expect(JSON.parse(tts.body)).toEqual({ text, model_id: "eleven_flash_v2_5" });
  });

  it("voices approvals without calling GPT", async () => {
    const { user, auth } = await signedInUser();
    await giveSubscription(user.id);
    const mock = providers();
    restore = mock.restore;
    const res = await post({ kind: "approval", agent: "Claude", name: "auth service", text: "auth service needs approval to remove node_modules directory." }, auth);
    expect(res.status).toBe(200);
    expect((await res.json<{ text: string }>()).text).toBe("auth service needs approval to remove node_modules directory.");
    expect(mock.calls.map((c) => new URL(c.url).host)).toEqual(["api.elevenlabs.io"]);
  });

  it("refuses without a subscription and when credits run out", async () => {
    const { user, auth } = await signedInUser();
    expect((await post(summaryBody, auth)).status).toBe(402);
    expect(await (await post(summaryBody, auth)).json()).toEqual({ error: "no_subscription" });

    await giveSubscription(user.id, { credits: 150000, used: 150000 });
    const res = await post(summaryBody, auth);
    expect(res.status).toBe(402);
    expect((await res.json<{ error: string }>()).error).toBe("credits_exhausted");
  });

  it("refuses when the line would exceed remaining credits", async () => {
    const { user, auth } = await signedInUser();
    await giveSubscription(user.id, { credits: 150000, used: 149990 });
    restore = providers().restore;
    const res = await post(summaryBody, auth);
    expect(res.status).toBe(402);
  });

  it("refuses expired subscriptions", async () => {
    const { user, auth } = await signedInUser();
    await giveSubscription(user.id, { status: "expired" });
    expect((await post(summaryBody, auth)).status).toBe(402);
  });

  it("falls back to the trimmed reply when GPT fails, and refunds if voice fails", async () => {
    const { user, auth } = await signedInUser();
    await giveSubscription(user.id, { credits: 1000 });
    let mock = mockFetch({
      "https://api.openai.com/": () => new Response("down", { status: 500 }),
      "https://api.elevenlabs.io/": () => new Response(mp3),
    });
    restore = mock.restore;
    const res = await post(summaryBody, auth);
    expect(res.status).toBe(200);
    expect((await res.json<{ text: string }>()).text).toBe("tool timeout mcp: I added a timeout to the MCP client and all tests pass.");
    mock.restore();

    mock = mockFetch({ "https://api.elevenlabs.io/": () => new Response("no", { status: 503 }) });
    restore = mock.restore;
    const before = await testEnv.DB.prepare("SELECT credits_used FROM subscriptions WHERE user_id = ?1").bind(user.id).first<number>("credits_used");
    const failed = await post({ kind: "approval", agent: "Claude", name: "x", text: "x needs approval to run ls." }, auth);
    expect(failed.status).toBe(502);
    const after = await testEnv.DB.prepare("SELECT credits_used FROM subscriptions WHERE user_id = ?1").bind(user.id).first<number>("credits_used");
    expect(after).toBe(before);
  });

  it("rejects bad requests", async () => {
    const { user, auth } = await signedInUser();
    await giveSubscription(user.id);
    expect((await post({ kind: "poem", name: "x" }, auth)).status).toBe(400);
    expect((await post({ kind: "approval", name: "x" }, auth)).status).toBe(400);
    expect((await post({ kind: "summary" }, auth)).status).toBe(400);
  });
});

describe("text helpers", () => {
  it("cleans markdown for speech", () => {
    expect(clean("I updated **`login.rs`** — see [docs](https://x.dev) or https://y.dev\n\n```js\ncode()\n```")).toBe(
      "I updated login.rs — see docs or a link",
    );
  });

  it("caps long lines on a sentence or word boundary", () => {
    const long = `${"First sentence is fine and long enough to keep. ".repeat(3)}${"word ".repeat(60)}`;
    const capped = capSpoken(long);
    expect([...capped].length).toBeLessThanOrEqual(223);
    expect(capped.endsWith(".") || capped.endsWith("...")).toBe(true);
  });

  it("builds fallbacks", () => {
    const req = parseRequest({ kind: "summary", name: "web", final_message: "Fixed it. Tests pass. Want more?" })!;
    expect(fallbackLine(req)).toBe("web: Fixed it. Tests pass.");
    expect(fallbackLine(parseRequest({ kind: "stop_failure", name: "web", error: "rate_limit" })!)).toBe("Heads up, web stopped because of an error.");
  });
});
