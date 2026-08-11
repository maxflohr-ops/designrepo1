import { createSign, createPrivateKey } from "node:crypto";
import { connect } from "node:http2";

// Token-based APNs sender — ES256 provider JWT + HTTP/2, no SDK.
// Env: APNS_KEY_P8 (the .p8 contents), APNS_KEY_ID, APNS_TEAM_ID,
// APNS_BUNDLE_ID (com.bountysounds.ios), APNS_HOST override for sandbox
// (api.sandbox.push.apple.com) — production host by default.
// Silent no-op until the key is configured, so the wire keeps working
// everywhere push isn't set up.

let cachedJwt: { token: string; issuedAt: number } | null = null;

export function apnsConfigured(): boolean {
  return !!(process.env.APNS_KEY_P8 && process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID);
}

const b64url = (input: Buffer | string) =>
  Buffer.from(input).toString("base64url");

// Apple wants provider tokens refreshed between 20 and 60 minutes; reuse for 40.
export function apnsProviderJwt(now = Date.now()): string {
  if (cachedJwt && now - cachedJwt.issuedAt < 40 * 60_000) return cachedJwt.token;
  const header = b64url(JSON.stringify({ alg: "ES256", kid: process.env.APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: process.env.APNS_TEAM_ID, iat: Math.floor(now / 1000) }));
  const signer = createSign("sha256");
  signer.update(`${header}.${claims}`);
  const signature = signer.sign(
    { key: createPrivateKey(process.env.APNS_KEY_P8!), dsaEncoding: "ieee-p1363" },
  );
  const token = `${header}.${claims}.${b64url(signature)}`;
  cachedJwt = { token, issuedAt: now };
  return token;
}

export async function sendApnsAlert(deviceToken: string, body: string): Promise<boolean> {
  if (!apnsConfigured()) return false;
  const host = process.env.APNS_HOST ?? "https://api.push.apple.com";
  return new Promise((resolve) => {
    const client = connect(host);
    client.on("error", () => resolve(false));
    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${apnsProviderJwt()}`,
      "apns-topic": process.env.APNS_BUNDLE_ID ?? "com.bountysounds.ios",
      "apns-push-type": "alert",
      "apns-priority": "10",
    });
    req.setEncoding("utf8");
    req.on("response", (headers) => {
      const ok = headers[":status"] === 200;
      req.on("end", () => { client.close(); resolve(ok); });
      req.resume();
    });
    req.on("error", () => { client.close(); resolve(false); });
    req.end(JSON.stringify({ aps: { alert: { body }, sound: "default" } }));
  });
}
