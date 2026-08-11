import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { buildServer } from "../src/api/server.js";
import { FakeStripe } from "../src/gateways/stripe.js";
import { StubTikTok } from "../src/gateways/tiktok.js";
import { pool, resetDb } from "./helpers.js";

const stripe = new FakeStripe();
const tiktok = new StubTikTok();
const app = buildServer({ stripe, tiktok });

const idem = () => ({ "idempotency-key": randomUUID() });

async function login(handle: string, role: "clipper" | "artist" = "clipper") {
  const res = await app.inject({
    method: "POST", url: "/v1/auth/tiktok", payload: { code: `oid_${handle}`, role },
  });
  const { token, account } = res.json();
  tiktok.seedProfile({
    openId: `oid_${handle}`, handle, followerCount: 9000, accountAgeDays: 900,
  });
  return { token, account, h: { authorization: `Bearer ${token}` } };
}

async function postFundedBounty(artistH: Record<string, string>, over: Record<string, unknown> = {}) {
  const { rows: [sound] } = await pool.query(
    `insert into sound (tiktok_music_id, title) values ('m_api', 'Ridge Club')
     on conflict (tiktok_music_id) do update set title = excluded.title returning *`);
  const res = await app.inject({
    method: "POST", url: "/v1/bounties", headers: { ...artistH, ...idem() },
    payload: {
      soundId: sound.id, title: "Clip the Thursday stream", brief: "Best 20 seconds.",
      payoutModel: "per_view", rateCents: 500, rateUnit: 5000, purseCents: 50_000,
      slotCap: 12, deadlineAt: new Date(Date.now() + 10 * 86400_000).toISOString(),
      ...over,
    },
  });
  expect(res.statusCode).toBe(201);
  const { bounty, clientSecret } = res.json();
  const wh = await app.inject({
    method: "POST", url: "/v1/stripe/webhook", headers: { "x-webhook-secret": "whsec_dev" },
    payload: {
      type: "payment_intent.succeeded",
      data: { object: { id: clientSecret.replace(/_secret_test$/, ""), amount: bounty.purse_cents } },
    },
  });
  expect(wh.statusCode).toBe(200);
  return bounty;
}

describe("REST API (§6)", () => {
  beforeAll(resetDb);
  afterAll(() => app.close());

  it("runs the whole clipper journey over HTTP", async () => {
    const artist = await login("ridgeclub", "artist");
    const clipper = await login("merrowcuts");
    const bounty = await postFundedBounty(artist.h);

    // board shows it, with ETag support
    const board = await app.inject({ method: "GET", url: "/v1/board", headers: clipper.h });
    expect(board.statusCode).toBe(200);
    expect(board.json().bounties).toHaveLength(1);
    const etag = board.headers.etag as string;
    const cached = await app.inject({
      method: "GET", url: "/v1/board", headers: { ...clipper.h, "if-none-match": etag },
    });
    expect(cached.statusCode).toBe(304);

    // detail payload carries the captured panel
    const detail = await app.inject({ method: "GET", url: `/v1/bounties/${bounty.id}`, headers: clipper.h });
    expect(detail.json().bounty.serial).toMatch(/^B \d{8}$/);

    // seize it
    const claimRes = await app.inject({
      method: "POST", url: `/v1/bounties/${bounty.id}/claims`, headers: { ...clipper.h, ...idem() },
    });
    expect(claimRes.statusCode).toBe(201);
    const claim = claimRes.json().claim;

    // checklist round-trip
    const patch = await app.inject({
      method: "PATCH", url: `/v1/claims/${claim.id}`, headers: clipper.h,
      payload: { checklist: [true, true, false, false] },
    });
    expect(patch.json().claim.checklist).toEqual([true, true, false, false]);

    // lodge the submission; the four checks run synchronously
    tiktok.seedVideo({
      videoId: "vapi", authorOpenId: "oid_merrowcuts", musicId: "m_api",
      isPublic: true, viewCount: 0, postedAt: new Date(),
    });
    const subRes = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/submission`,
      headers: { ...clipper.h, ...idem() }, payload: { tiktokVideoId: "vapi" },
    });
    expect(subRes.statusCode).toBe(201);
    const { submission, checks } = subRes.json();
    expect(checks).toEqual({
      sound_match: true, posted_in_window: true, handle_verified: true, duplicate_clear: true,
    });

    // views land, artist approves, purse shows payable
    tiktok.videos.get("vapi")!.viewCount = 88_000;
    await app.services.counting.pollSubmission(submission.id);
    const verdict = await app.inject({
      method: "POST", url: `/v1/submissions/${submission.id}/verdict`,
      headers: { ...artist.h, ...idem() }, payload: { verdict: "approve" },
    });
    expect(verdict.json()).toMatchObject({ state: "paid", paidCents: 8800 });

    const purse = await app.inject({ method: "GET", url: "/v1/me/purse", headers: clipper.h });
    expect(purse.json()).toMatchObject({ payableCents: 8800, lifetimeCents: 8800 });
    expect(purse.json().feed.length).toBeGreaterThan(0);

    // cash out needs attestation, then the first-payout hold applies
    const noAttest = await app.inject({
      method: "POST", url: "/v1/me/payouts", headers: { ...clipper.h, ...idem() },
      payload: { amountCents: 8800 },
    });
    expect(noAttest.statusCode).toBe(403);
    const held = await app.inject({
      method: "POST", url: "/v1/me/payouts",
      headers: { ...clipper.h, ...idem(), "x-device-attestation": "appattest_ok" },
      payload: { amountCents: 8800 },
    });
    expect(held.statusCode).toBe(403);
    expect(held.json().error).toBe("first_payout_hold");

    // the wire carried the story
    const wire = await app.inject({ method: "GET", url: "/v1/me/wire", headers: clipper.h });
    expect(wire.json().items.map((i: { body: string }) => i.body).join(" ")).toContain("cleared");

    // the desk endpoint shows the settled claim with its submission
    const claims = await app.inject({ method: "GET", url: "/v1/me/claims", headers: clipper.h });
    expect(claims.json().claims[0]).toMatchObject({
      state: "settled", submission_state: "paid", accrued_cents: 8800,
    });
  });

  it("replays idempotent claims instead of double-claiming", async () => {
    const artist = await login("artist_i", "artist");
    const clipper = await login("clipper_i");
    const bounty = await postFundedBounty(artist.h);
    const key = { "idempotency-key": "claim-once" };

    const first = await app.inject({
      method: "POST", url: `/v1/bounties/${bounty.id}/claims`, headers: { ...clipper.h, ...key },
    });
    const second = await app.inject({
      method: "POST", url: `/v1/bounties/${bounty.id}/claims`, headers: { ...clipper.h, ...key },
    });
    expect(second.statusCode).toBe(201);
    expect(second.json().claim.id).toBe(first.json().claim.id);
    const { rows } = await pool.query(
      "select count(*)::int as n from claim where account_id = $1", [clipper.account.id]);
    expect(rows[0].n).toBe(1);

    // same key, different body → 422; no key → 400
    const misuse = await app.inject({
      method: "POST", url: `/v1/bounties/${bounty.id}/claims?x=1`, headers: { ...clipper.h, ...key },
    });
    expect(misuse.statusCode).toBe(422);
    const bare = await app.inject({
      method: "POST", url: `/v1/bounties/${bounty.id}/claims`, headers: clipper.h,
    });
    expect(bare.statusCode).toBe(400);
  });

  it("rejects a submission that fails the automatic checks", async () => {
    const artist = await login("artist_c", "artist");
    const clipper = await login("clipper_c");
    const bounty = await postFundedBounty(artist.h);
    const claim = (await app.inject({
      method: "POST", url: `/v1/bounties/${bounty.id}/claims`, headers: { ...clipper.h, ...idem() },
    })).json().claim;

    tiktok.seedVideo({
      videoId: "wrongsound", authorOpenId: "oid_clipper_c", musicId: "not_the_contract_audio",
      isPublic: true, viewCount: 0, postedAt: new Date(),
    });
    const res = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/submission`,
      headers: { ...clipper.h, ...idem() }, payload: { tiktokVideoId: "wrongsound" },
    });
    expect(res.statusCode).toBe(422);
    expect(res.json().checks.sound_match).toBe(false);
    expect(res.json().submission.state).toBe("rejected");
  });

  it("filters the board by deep-linked sound and paginates by cursor", async () => {
    await resetDb();
    const artist = await login("artist_p", "artist");
    const clipper = await login("clipper_p");
    for (let i = 0; i < 3; i++) await postFundedBounty(artist.h, { title: `Bounty ${i}` });

    const page1 = await app.inject({ method: "GET", url: "/v1/board?limit=2", headers: clipper.h });
    expect(page1.json().bounties).toHaveLength(2);
    expect(page1.json().nextCursor).toBeTruthy();
    const page2 = await app.inject({
      method: "GET", url: `/v1/board?limit=2&cursor=${page1.json().nextCursor}`, headers: clipper.h,
    });
    expect(page2.json().bounties).toHaveLength(1);

    const filtered = await app.inject({
      method: "GET", url: "/v1/board?sound=m_api", headers: clipper.h });
    expect(filtered.json().bounties.length).toBe(3);
    const none = await app.inject({
      method: "GET", url: "/v1/board?sound=other", headers: clipper.h });
    expect(none.json().bounties.length).toBe(0);
  });

  it("artist tops up and reviews; chargeback suspends posting", async () => {
    await resetDb();
    const artist = await login("artist_t", "artist");
    const clipper = await login("clipper_t");
    const bounty = await postFundedBounty(artist.h);

    const topup = await app.inject({
      method: "POST", url: `/v1/bounties/${bounty.id}/topups`,
      headers: { ...artist.h, ...idem() }, payload: { amountCents: 25_000 },
    });
    expect(topup.statusCode).toBe(201);
    const intentId = topup.json().clientSecret.replace(/_secret_test$/, "");
    await app.inject({
      method: "POST", url: "/v1/stripe/webhook", headers: { "x-webhook-secret": "whsec_dev" },
      payload: { type: "payment_intent.succeeded", data: { object: { id: intentId, amount: 25_000 } } },
    });
    const { rows: [b] } = await pool.query("select purse_cents from bounty where id = $1", [bounty.id]);
    expect(b.purse_cents).toBe(75_000);

    // clipper submits; artist review feed shows it
    const claim = (await app.inject({
      method: "POST", url: `/v1/bounties/${bounty.id}/claims`, headers: { ...clipper.h, ...idem() },
    })).json().claim;
    tiktok.seedVideo({
      videoId: "vt", authorOpenId: "oid_clipper_t", musicId: "m_api",
      isPublic: true, viewCount: 12_000, postedAt: new Date(),
    });
    const sub = (await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/submission`,
      headers: { ...clipper.h, ...idem() }, payload: { tiktokVideoId: "vt" },
    })).json().submission;
    await app.services.counting.pollSubmission(sub.id);
    const review = await app.inject({ method: "GET", url: "/v1/me/review", headers: artist.h });
    expect(review.json().submissions[0]).toMatchObject({ handle: "clipper_t", state: "counting" });

    // chargeback lands → posting is blocked (§8 Q4)
    const { rows: [bb] } = await pool.query(
      "select stripe_payment_intent_id from bounty where id = $1", [bounty.id]);
    await app.inject({
      method: "POST", url: "/v1/stripe/webhook", headers: { "x-webhook-secret": "whsec_dev" },
      payload: {
        type: "charge.dispute.created",
        data: { object: { payment_intent: bb.stripe_payment_intent_id, amount: 75_000 } },
      },
    });
    const blocked = await app.inject({
      method: "POST", url: "/v1/bounties", headers: { ...artist.h, ...idem() },
      payload: {
        soundId: randomUUID(), title: "x", payoutModel: "per_view",
        rateCents: 500, purseCents: 1000, deadlineAt: new Date().toISOString(),
      },
    });
    expect(blocked.statusCode).toBe(403);
    expect(blocked.json().error).toBe("suspended");
  });

  it("refuses Shorts bounties in v1 (§8 Q3)", async () => {
    const artist = await login("artist_s", "artist");
    const { rows: [sound] } = await pool.query(
      `insert into sound (tiktok_music_id, title) values ('m_shorts', 'Keynote')
       on conflict (tiktok_music_id) do update set title = excluded.title returning *`);
    const res = await app.inject({
      method: "POST", url: "/v1/bounties", headers: { ...artist.h, ...idem() },
      payload: {
        soundId: sound.id, title: "Keynote pull-quotes", payoutModel: "per_view",
        rateCents: 800, rateUnit: 10000, purseCents: 120_000, platform: "shorts",
        deadlineAt: new Date(Date.now() + 86400_000).toISOString(),
      },
    });
    expect(res.statusCode).toBe(422);
    expect(res.json().error).toBe("platform_unsupported");
  });
});

describe("counting job scheduling", () => {
  beforeEach(resetDb);

  it("decays the cadence: hourly → six-hourly → daily", async () => {
    const { cadenceMinutes } = await import("../src/modules/counting/service.js");
    const posted = new Date("2026-08-01T00:00:00Z");
    expect(cadenceMinutes(posted, new Date("2026-08-01T10:00:00Z"))).toBe(60);
    expect(cadenceMinutes(posted, new Date("2026-08-04T00:00:00Z"))).toBe(360);
    expect(cadenceMinutes(posted, new Date("2026-08-10T00:00:00Z"))).toBe(1440);
    expect(cadenceMinutes(posted, new Date("2026-08-16T00:00:00Z"))).toBeNull();
  });

  it("over budget, polls degrade to the next tier and the next sample says so", async () => {
    const { fundedBountyWithSubmission } = await import("./helpers.js");
    const { config } = await import("../src/config.js");
    const { svc, submission } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 1000;

    const saved = config.pollBudgetPerRun;
    config.pollBudgetPerRun = 0;
    try {
      // poll "from the future" so DB-clock vs JS-clock skew can't hide the row
      await svc.counting.runOnce(new Date(Date.now() + 5000));
      const { rows: [s] } = await pool.query(
        "select degrade_next, next_poll_at from submission where id = $1", [submission.id]);
      expect(s.degrade_next).toBe(true);
      expect(new Date(s.next_poll_at).getTime()).toBeGreaterThan(Date.now() + 300 * 60_000);

      config.pollBudgetPerRun = saved;
      await pool.query("update submission set next_poll_at = now() where id = $1", [submission.id]);
      await svc.counting.runOnce(new Date(Date.now() + 5000));
      const { rows: [sample] } = await pool.query(
        "select anomaly_flags from view_sample where submission_id = $1 order by id desc limit 1",
        [submission.id]);
      expect(sample.anomaly_flags).toContain("degraded");
    } finally {
      config.pollBudgetPerRun = saved;
    }
  });

  it("closes the window into payable when the cadence runs out", async () => {
    const { fundedBountyWithSubmission } = await import("./helpers.js");
    const { svc, submission } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 44_000;
    await pool.query(
      `update submission set posted_at = now() - interval '15 days',
              window_ends_at = now() - interval '1 day' where id = $1`, [submission.id]);
    await svc.counting.pollSubmission(submission.id);
    const { rows: [s] } = await pool.query(
      "select state, next_poll_at, accrued_cents from submission where id = $1", [submission.id]);
    expect(s.state).toBe("payable");
    expect(s.next_poll_at).toBeNull();
    expect(s.accrued_cents).toBe(4_400);
  });
});
