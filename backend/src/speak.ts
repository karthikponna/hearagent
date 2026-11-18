import { Hono } from "hono";
import OpenAI from "openai";
import { base64 } from "./crypto";
import { creditsRemaining, getSubscription, hasAccess, isoOrNull, refundCredits, spendCredits } from "./db";
import type { AppContext, AppEnv } from "./env";

const MAX_SPOKEN_CHARS = 220;

type Kind = "approval" | "summary" | "stop_failure";

interface Digest {
  prompt?: string;
  files_changed?: string[];
  commands?: string[];
  failures?: string[];
  tool_calls?: number;
  final_reply?: string;
}

export interface SpeakRequest {
  kind: Kind;
  agent: string;
  name: string;
  text?: string;
  final_message?: string;
  digest?: Digest;
  error?: string;
}

const SUMMARY_INSTRUCTIONS = `You are Hear Agent, a friendly voice that tells a developer what their AI coding agent just finished. The developer is not looking at the screen: your words are read aloud.

Write ONE spoken update:
- Begin with the session name exactly as given, for example "Hey, {name} just wrapped up..." or "{name} is done...".
- Sound like a relaxed teammate. One or two short sentences, under 35 words in total.
- Say the outcome: what was built, fixed, or answered, and whether tests or builds pass when that is known.
- If something failed along the way but was fixed, mention it in a few words. If something still fails, say so clearly.
- If the agent ended by asking the developer a question, say it is waiting for an answer and give the gist of the question.
- No markdown, code, file paths, URLs, or long identifiers. Mention a file name only if it really matters.
- Never invent anything that is not in the input.`;

const STOP_FAILURE_INSTRUCTIONS = `You are Hear Agent, a voice that alerts a developer when their AI coding agent stops unexpectedly. Your words are read aloud.

Write ONE short spoken sentence, under 25 words:
- Begin with the session name exactly as given, for example "Heads up, {name} stopped...".
- Explain the reason in plain words: a rate limit, the service being overloaded, an authentication problem, or another error.
- No markdown, codes, or jargon. Never invent details.`;

export const speak = new Hono<AppContext>();

speak.post("/", async (c) => {
  const req = parseRequest(await c.req.json().catch(() => null));
  if (!req) return c.json({ error: "invalid_request" }, 400);

  const user = c.get("user");
  const sub = await getSubscription(c.env.DB, user.id);
  if (!sub || !hasAccess(sub)) return c.json({ error: "no_subscription" }, 402);
  if (creditsRemaining(sub) <= 0) {
    return c.json({ error: "credits_exhausted", period_end: isoOrNull(sub.period_end) }, 402);
  }

  const text = capSpoken(await writeLine(c.env, req));
  const cost = [...text].length;
  if (!(await spendCredits(c.env.DB, user.id, cost))) {
    return c.json({ error: "credits_exhausted", period_end: isoOrNull(sub.period_end) }, 402);
  }

  let audio: { data: ArrayBuffer; format: string };
  try {
    audio = await synthesize(c.env, text);
  } catch (e) {
    await refundCredits(c.env.DB, user.id, cost);
    console.log(JSON.stringify({ event: "tts_error", message: String(e) }));
    return c.json({ error: "tts_failed" }, 502);
  }

  const remaining = creditsRemaining({ ...sub, credits_used: sub.credits_used + cost });
  console.log(JSON.stringify({ event: "speak", kind: req.kind, chars: cost, user: user.id }));
  return c.json({
    text,
    audio_base64: base64(audio.data),
    audio_format: audio.format,
    credits_remaining: remaining,
    credits_total: sub.credits_total,
    period_end: isoOrNull(sub.period_end),
  });
});

export function parseRequest(body: unknown): SpeakRequest | null {
  if (!body || typeof body !== "object") return null;
  const b = body as Record<string, unknown>;
  const str = (v: unknown, max: number) => (typeof v === "string" ? v.slice(0, max) : undefined);
  const kind = b.kind;
  if (kind !== "approval" && kind !== "summary" && kind !== "stop_failure") return null;
  const name = str(b.name, 120)?.trim();
  if (!name) return null;
  const req: SpeakRequest = {
    kind,
    name,
    agent: str(b.agent, 40) ?? "Claude",
    text: str(b.text, 300),
    final_message: str(b.final_message, 6000),
    error: str(b.error, 600),
  };
  if (b.digest && typeof b.digest === "object") {
    const d = b.digest as Record<string, unknown>;
    const list = (v: unknown, n: number) => (Array.isArray(v) ? v.filter((x) => typeof x === "string").slice(0, n).map((x) => String(x).slice(0, 200)) : []);
    req.digest = {
      prompt: str(d.prompt, 400),
      files_changed: list(d.files_changed, 12),
      commands: list(d.commands, 8),
      failures: list(d.failures, 6),
      tool_calls: typeof d.tool_calls === "number" ? d.tool_calls : undefined,
      final_reply: str(d.final_reply, 4000),
    };
  }
  if (kind === "approval" && !req.text?.trim()) return null;
  return req;
}

/** The sentence to speak. Falls back to a trimmed reply if the model is unavailable. */
export async function writeLine(env: AppEnv, req: SpeakRequest): Promise<string> {
  if (req.kind === "approval") return clean(req.text ?? "");
  if (env.MOCK_PROVIDERS === "1") {
    return req.kind === "summary" ? `Hey, ${req.name} just wrapped up the task.` : `Heads up, ${req.name} stopped early.`;
  }
  try {
    const client = new OpenAI({ apiKey: env.OPENAI_API_KEY });
    const response = await client.responses.create({
      model: env.OPENAI_MODEL,
      instructions: req.kind === "summary" ? SUMMARY_INSTRUCTIONS : STOP_FAILURE_INSTRUCTIONS,
      input: JSON.stringify(modelInput(req)),
      reasoning: { effort: "minimal" },
      max_output_tokens: 400,
      store: false,
    });
    const text = clean(response.output_text ?? "");
    if (text) return text;
  } catch (e) {
    console.log(JSON.stringify({ event: "llm_error", message: String(e) }));
  }
  return fallbackLine(req);
}

function modelInput(req: SpeakRequest) {
  if (req.kind === "stop_failure") {
    return { session_name: req.name, agent: req.agent, error: req.error ?? "unknown error" };
  }
  const d = req.digest ?? {};
  return {
    session_name: req.name,
    agent: req.agent,
    task: d.prompt,
    files_changed: d.files_changed,
    commands_run: d.commands,
    failures_during_run: d.failures,
    final_reply: req.final_message || d.final_reply,
  };
}

/** Used when the model call fails: the agent's own words, trimmed. */
export function fallbackLine(req: SpeakRequest): string {
  if (req.kind === "stop_failure") return `Heads up, ${req.name} stopped because of an error.`;
  const reply = clean(req.final_message || req.digest?.final_reply || "");
  const sentences = reply.match(/[^.!?]+[.!?]+(\s|$)/g)?.map((s) => s.trim()) ?? (reply ? [reply] : []);
  const gist = sentences.slice(0, 2).join(" ");
  return gist ? `${req.name}: ${gist}` : `${req.name} just finished.`;
}

/** Strips markdown and code that would sound bad aloud. */
export function clean(text: string): string {
  return text
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/`([^`]*)`/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/https?:\/\/\S+/g, "a link")
    .replace(/[*#>|]+/g, "")
    .replace(/(^|\s)_+|_+(?=\s|$|[.,!?])/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

export function capSpoken(text: string): string {
  const chars = [...text];
  if (chars.length <= MAX_SPOKEN_CHARS) return text;
  const cut = chars.slice(0, MAX_SPOKEN_CHARS).join("");
  const lastStop = Math.max(cut.lastIndexOf(". "), cut.lastIndexOf("! "), cut.lastIndexOf("? "));
  if (lastStop > 80) return cut.slice(0, lastStop + 1);
  return `${cut.slice(0, cut.lastIndexOf(" ")).replace(/[,;:]$/, "")}...`;
}

async function synthesize(env: AppEnv, text: string): Promise<{ data: ArrayBuffer; format: string }> {
  if (env.MOCK_PROVIDERS === "1") return { data: beepWav(), format: "wav" };
  const url = `https://api.elevenlabs.io/v1/text-to-speech/${env.ELEVENLABS_VOICE_ID}?output_format=mp3_44100_128`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "xi-api-key": env.ELEVENLABS_API_KEY, "Content-Type": "application/json", Accept: "audio/mpeg" },
    body: JSON.stringify({ text, model_id: env.ELEVENLABS_MODEL }),
  });
  if (!res.ok) throw new Error(`elevenlabs ${res.status}`);
  return { data: await res.arrayBuffer(), format: "mp3" };
}

/** A short two-tone WAV, so local testing exercises real audio playback. */
function beepWav(): ArrayBuffer {
  const rate = 16000;
  const samples = Math.floor(rate * 0.6);
  const buf = new ArrayBuffer(44 + samples * 2);
  const v = new DataView(buf);
  const ascii = (o: number, s: string) => [...s].forEach((ch, i) => v.setUint8(o + i, ch.charCodeAt(0)));
  ascii(0, "RIFF");
  v.setUint32(4, 36 + samples * 2, true);
  ascii(8, "WAVEfmt ");
  v.setUint32(16, 16, true);
  v.setUint16(20, 1, true);
  v.setUint16(22, 1, true);
  v.setUint32(24, rate, true);
  v.setUint32(28, rate * 2, true);
  v.setUint16(32, 2, true);
  v.setUint16(34, 16, true);
  ascii(36, "data");
  v.setUint32(40, samples * 2, true);
  for (let i = 0; i < samples; i++) {
    const freq = i < samples / 2 ? 660 : 880;
    v.setInt16(44 + i * 2, Math.round(Math.sin((2 * Math.PI * freq * i) / rate) * 8000), true);
  }
  return buf;
}
