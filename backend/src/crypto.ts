const encoder = new TextEncoder();

export function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let bin = "";
  for (const b of arr) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let bin = "";
  for (let i = 0; i < arr.length; i += 0x8000) {
    bin += String.fromCharCode(...arr.subarray(i, i + 0x8000));
  }
  return btoa(bin);
}

export function fromBase64(s: string): Uint8Array {
  const normalized = s.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

export function randomToken(bytes = 32): string {
  return base64url(crypto.getRandomValues(new Uint8Array(bytes)));
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Base64url(value: string): Promise<string> {
  return base64url(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}

async function hmacKey(secret: Uint8Array | string): Promise<CryptoKey> {
  const raw = typeof secret === "string" ? encoder.encode(secret) : secret;
  return crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
}

export async function hmacSha256(secret: Uint8Array | string, message: string): Promise<Uint8Array> {
  const key = await hmacKey(secret);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(message)));
}

export function timingSafeEqual(a: string, b: string): boolean {
  const ab = encoder.encode(a);
  const bb = encoder.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

/** Signs a small JSON payload: "<payload>.<signature>", both base64url. */
export async function signPayload(secret: string, payload: object): Promise<string> {
  const body = base64url(encoder.encode(JSON.stringify(payload)));
  const sig = base64url(await hmacSha256(secret, body));
  return `${body}.${sig}`;
}

export async function verifyPayload<T>(secret: string, token: string): Promise<T | null> {
  const [body, sig] = token.split(".");
  if (!body || !sig) return null;
  const expected = base64url(await hmacSha256(secret, body));
  if (!timingSafeEqual(sig, expected)) return null;
  try {
    return JSON.parse(new TextDecoder().decode(fromBase64(body))) as T;
  } catch {
    return null;
  }
}

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}
