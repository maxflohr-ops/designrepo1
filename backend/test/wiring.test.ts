import { beforeAll, afterAll, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { buildServer } from "../src/api/server.js";
import { signStripePayload, verifyStripeSignature } from "../src/api/stripeSignature.js";
import { FakeStripe } from "../src/gateways/stripe.js";
import { StubTikTok } from "../src/gateways/tiktok.js";
import { getTikTokTokens, saveTikTokTokens } from "../src/modules/identity/tokens.js";
import { pool, resetDb } from "./helpers.js";
import { redis } from "../src/redis.js";

const stripe = new FakeStripe();
const tiktok = new StubTikTok();
const app = buildServer({ stripe, tiktok });
const idem = () => ({ "idempotency-key": randomUUID() });

async function login(handle: string, role: "clipper" | "artist" = "clipper") {
  const res = await app.inject({
    method: "POST", url: "/v1/auth/tiktok", payload: { code: `oid_${handle}`, role },
    remoteAddress: `10.0.0.${Math.floor(Math.random() * 250) + 1}`,
  });
  const { token, account } = res.json();
  tiktok.seedProfile({ openId: `oid_${handle}`, handle, followerCount: 9000, accountAgeDays: 900 });
  return { token, account, h: { authorization: `Bearer ${token}` } };
}

describe("production wiring", () => {
  beforeAll(async () => {
    await resetDb();
    const keys = await redis.keys("rate:*");
    if (keys.length) await redis.del(keys);
  });
  afterAll(() => app.close());

  it("verifies real Stripe signatures and rejects bad ones", () => {
    const payload = JSON.stringify({ type: "payment_intent.succeeded" });
    const secret = "whsec_dev";
    const header = signStripePayload(payload, secret);
    expect(verifyStripeSignature(payload, header, secret)).toBe(true);
    expect(verifyStripeSignature(payload + " ", header, secret)).toBe(false);
    expect(verifyStripeSignature(payload, header, "whsec_other")).toBe(false);
    // stale timestamp outside tolerance
    const old = signStripePayload(payload, secret, Date.now() - 10 * 60_000);
    expect(verifyStripeSignature(payload, old, secret)).toBe(false);
    expect(verifyStripeSignature(payload, undefined, secret)).toBe(false);
  });

  it("accepts a signed webhook over HTTP and rejects an unsigned one without the dev fallback", async () => {
    const artist = await login("wire_artist", "artist");
    const { rows: [sound] } = await pool.query(
      "insert into sound (tiktok_music_id, title) values ('m_wire', 'Wire') returning *");
    const draft = await app.inject({
      method: "POST", url: "/v1/bounties", headers: { ...artist.h, ...idem() },
      payload: {
        soundId: sound.id, title: "t", payoutModel: "per_view", rateCents: 500,
        rateUnit: 5000, purseCents: 10_000,
        deadlineAt: new Date(Date.now() + 86400_000).toISOString(),
      },
    });
    const intentId = draft.json().clientSecret.replace(/_secret_test$/, "");
    const payload = JSON.stringify({
      type: "payment_intent.succeeded", data: { object: { id: intentId, amount: 10_000 } },
    });

    const unsigned = await app.inject({
      method: "POST", url: "/v1/stripe/webhook",
      headers: { "content-type": "application/json" }, payload,
    });
    expect(unsigned.statusCode).toBe(401);

    const signed = await app.inject({
      method: "POST", url: "/v1/stripe/webhook",
      headers: {
        "content-type": "application/json",
        "stripe-signature": signStripePayload(payload, "whsec_dev"),
      },
      payload,
    });
    expect(signed.statusCode).toBe(200);
    const { rows: [b] } = await pool.query("select state from bounty where id = $1", [draft.json().bounty.id]);
    expect(b.state).toBe("live");
  });

  it("stores and updates TikTok tokens", async () => {
    await saveTikTokTokens("oid_tok", {
      accessToken: "acc1", refreshToken: "ref1", expiresInSec: 3600, scopes: ["user.info.basic"],
    });
    let t = await getTikTokTokens("oid_tok");
    expect(t?.accessToken).toBe("acc1");
    expect(t?.expiresAt.getTime()).toBeGreaterThan(Date.now() + 3000_000);
    // refresh path keeps the old refresh token when none is returned
    await saveTikTokTokens("oid_tok", { accessToken: "acc2", expiresInSec: 100 });
    t = await getTikTokTokens("oid_tok");
    expect(t?.accessToken).toBe("acc2");
    expect(t?.refreshToken).toBe("ref1");
  });

  it("serves the roster ranked by 90-day payouts", async () => {
    const { fundedBountyWithSubmission } = await import("./helpers.js");
    const { svc, artist, clipper, submission } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 88_000;
    await svc.counting.pollSubmission(submission.id);
    await svc.bounties.verdict(artist.id, submission.id, "approve");

    const session = await app.inject({
      method: "POST", url: "/v1/auth/tiktok",
      payload: { code: clipper.tiktok_open_id, role: "clipper" },
      remoteAddress: "10.9.9.9",
    });
    const res = await app.inject({
      method: "GET", url: "/v1/roster",
      headers: { authorization: `Bearer ${session.json().token}` },
    });
    const roster = res.json().roster;
    expect(roster).toHaveLength(1);
    expect(roster[0]).toMatchObject({
      rank: 1, isYou: true, handle: "merrowcuts", paid_cents: 8800, bounties: 1,
      paid_views: 88_000, points: 88,
    });
  });

  it("gates payouts on registered App Attest keys", async () => {
    const clipper = await login("attest_clip");
    // give the account payable balance directly through the service layer
    const { postTxn, refs } = await import("../src/domain/ledger.js");
    await postTxn(pool, "cash_out", [
      { ref: refs.payable(clipper.account.id), direction: "credit", amountCents: 5000 },
      { ref: refs.externalClipper(clipper.account.id), direction: "debit", amountCents: 5000 },
    ]);
    // …and a prior cash_out so the first-payout hold doesn't interfere
    await postTxn(pool, "cash_out", [
      { ref: refs.payable(clipper.account.id), direction: "debit", amountCents: 1 },
      { ref: refs.externalClipper(clipper.account.id), direction: "credit", amountCents: 1 },
    ]);

    const attest = await app.inject({
      method: "POST", url: "/v1/me/attest", headers: clipper.h,
      payload: { keyId: "keyid-ABC12345", attestation: "base64-attestation-object-000" },
    });
    expect(attest.statusCode).toBe(200);

    // wrong key → rejected now that a key is registered
    const wrong = await app.inject({
      method: "POST", url: "/v1/me/payouts",
      headers: { ...clipper.h, ...idem(), "x-device-attestation": "otherkey:assertion" },
      payload: { amountCents: 1000 },
    });
    expect(wrong.statusCode).toBe(403);
    expect(wrong.json().error).toBe("attestation_invalid");

    const right = await app.inject({
      method: "POST", url: "/v1/me/payouts",
      headers: { ...clipper.h, ...idem(), "x-device-attestation": "keyid-ABC12345:assertion-bytes" },
      payload: { amountCents: 1000 },
    });
    expect(right.statusCode).toBe(201);
  });

  it("creates an Express account once and returns an onboarding link", async () => {
    const clipper = await login("payout_clip");
    const first = await app.inject({
      method: "POST", url: "/v1/me/payout-account", headers: { ...clipper.h, ...idem() },
    });
    expect(first.statusCode).toBe(201);
    const { accountId, onboardingUrl } = first.json();
    expect(accountId).toMatch(/^acct_/);
    expect(onboardingUrl).toContain("connect.stripe.com");

    // second call reuses the same connected account
    const second = await app.inject({
      method: "POST", url: "/v1/me/payout-account", headers: { ...clipper.h, ...idem() },
    });
    expect(second.json().accountId).toBe(accountId);
    expect(stripe.expressAccounts).toHaveLength(1);
    const { rows: [a] } = await pool.query(
      "select payout_method_id from account where id = $1", [clipper.account.id]);
    expect(a.payout_method_id).toBe(accountId);
  });

  it("rate limits the auth endpoint per IP", async () => {
    const ip = "10.200.1.1";
    let last = 0;
    for (let i = 0; i < 11; i++) {
      const res = await app.inject({
        method: "POST", url: "/v1/auth/tiktok",
        payload: { code: `oid_rl_${i}`, role: "clipper" },
        remoteAddress: ip,
      });
      last = res.statusCode;
    }
    expect(last).toBe(429);
  });

  it("bounces the TikTok OAuth callback into the app scheme", async () => {
    const res = await app.inject({
      method: "GET", url: "/v1/auth/tiktok/callback?code=abc123&state=xyz",
    });
    expect(res.statusCode).toBe(302);
    expect(res.headers.location).toBe("bountysounds://oauth?code=abc123&state=xyz");
  });

  it("healthz pings the database and redis", async () => {
    const res = await app.inject({ method: "GET", url: "/healthz" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
  });
});
