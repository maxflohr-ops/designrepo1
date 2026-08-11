import { createHmac, timingSafeEqual } from "node:crypto";

// Stripe webhook signature verification (the `Stripe-Signature` header:
// `t=<unix>,v1=<hmac>[,v1=…]`). HMAC-SHA256 over `${t}.${rawBody}` with the
// endpoint's signing secret. Implemented against Stripe's documented scheme
// so no SDK dependency is needed.
export function verifyStripeSignature(
  rawBody: string,
  header: string | undefined,
  secret: string,
  toleranceSec = 300,
  now = Date.now(),
): boolean {
  if (!header) return false;
  const parts = new Map<string, string[]>();
  for (const kv of header.split(",")) {
    const [k, v] = kv.split("=", 2);
    if (!k || !v) continue;
    parts.set(k.trim(), [...(parts.get(k.trim()) ?? []), v.trim()]);
  }
  const t = Number(parts.get("t")?.[0]);
  const signatures = parts.get("v1") ?? [];
  if (!Number.isFinite(t) || signatures.length === 0) return false;
  if (Math.abs(now / 1000 - t) > toleranceSec) return false;

  const expected = createHmac("sha256", secret).update(`${t}.${rawBody}`).digest("hex");
  const expectedBuf = Buffer.from(expected);
  return signatures.some((sig) => {
    const buf = Buffer.from(sig);
    return buf.length === expectedBuf.length && timingSafeEqual(buf, expectedBuf);
  });
}

// Test helper / stripe-cli substitute: produce a valid header for a payload.
export function signStripePayload(rawBody: string, secret: string, now = Date.now()): string {
  const t = Math.floor(now / 1000);
  const v1 = createHmac("sha256", secret).update(`${t}.${rawBody}`).digest("hex");
  return `t=${t},v1=${v1}`;
}
