import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { randomUUID } from "node:crypto";
import { buildServer } from "../src/api/server.js";
import { FakeStripe } from "../src/gateways/stripe.js";
import { StubTikTok } from "../src/gateways/tiktok.js";
import { config } from "../src/config.js";
import { pool, resetDb } from "./helpers.js";

const stripe = new FakeStripe();
const tiktok = new StubTikTok();
const app = buildServer({ stripe, tiktok });
const idem = () => ({ "idempotency-key": randomUUID() });

async function login(handle: string, role: "clipper" | "artist" = "clipper") {
  const res = await app.inject({
    method: "POST", url: "/v1/auth/tiktok", payload: { code: `oid_${handle}`, role },
    remoteAddress: `10.1.0.${Math.floor(Math.random() * 250) + 1}`,
  });
  const { token, account } = res.json();
  tiktok.seedProfile({ openId: `oid_${handle}`, handle, followerCount: 9000, accountAgeDays: 900 });
  return { token, account, h: { authorization: `Bearer ${token}` } };
}

// artist + funded bounty + clipper claim, over HTTP
async function claimReady() {
  const artist = await login("dp_artist", "artist");
  const clipper = await login("dp_clipper");
  const { rows: [sound] } = await pool.query(
    `insert into sound (tiktok_music_id, title) values ('m_dp', 'Ridge Club') returning *`);
  const draft = await app.inject({
    method: "POST", url: "/v1/bounties", headers: { ...artist.h, ...idem() },
    payload: {
      soundId: sound.id, title: "Clip the stream", payoutModel: "per_view",
      rateCents: 500, rateUnit: 5000, purseCents: 50_000,
      deadlineAt: new Date(Date.now() + 10 * 86400_000).toISOString(),
    },
  });
  const { bounty, clientSecret } = draft.json();
  await app.inject({
    method: "POST", url: "/v1/stripe/webhook",
    headers: { "x-webhook-secret": "whsec_dev" },
    payload: {
      type: "payment_intent.succeeded",
      data: { object: { id: clientSecret.replace(/_secret_test$/, ""), amount: bounty.purse_cents } },
    },
  });
  const claim = (await app.inject({
    method: "POST", url: `/v1/bounties/${bounty.id}/claims`, headers: { ...clipper.h, ...idem() },
  })).json().claim;
  return { artist, clipper, claim };
}

describe("direct post (Content Posting API)", () => {
  beforeEach(async () => {
    await resetDb();
    config.directPostEnabled = false;
  });
  afterAll(() => { config.directPostEnabled = false; return app.close(); });

  it("serves creator info with the posting capability flag", async () => {
    const clipper = await login("dp_info");
    const res = await app.inject({
      method: "GET", url: "/v1/me/tiktok/creator-info", headers: clipper.h });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({
      creator: { nickname: "dp_info", maxVideoDurationSec: 600 },
      directPostEnabled: false,
    });
    expect(res.json().creator.privacyOptions).toContain("PUBLIC_TO_EVERYONE");
  });

  it("refuses to start a post until TikTok's audit unlocks it", async () => {
    const { clipper, claim } = await claimReady();
    const res = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/direct-post`,
      headers: { ...clipper.h, ...idem() },
      payload: { caption: "thursday cut", privacyLevel: "PUBLIC_TO_EVERYONE", videoSizeBytes: 4_000_000 },
    });
    expect(res.statusCode).toBe(403);
    expect(res.json().error).toBe("direct_post_disabled");
  });

  it("posts through TikTok and lodges the submission from the returned video id", async () => {
    config.directPostEnabled = true;
    const { clipper, claim } = await claimReady();

    const start = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/direct-post`,
      headers: { ...clipper.h, ...idem() },
      payload: { caption: "thursday cut", privacyLevel: "PUBLIC_TO_EVERYONE", videoSizeBytes: 4_000_000 },
    });
    expect(start.statusCode).toBe(201);
    const { publishId, uploadUrl } = start.json();
    expect(uploadUrl).toContain(publishId);
    const { rows: [stored] } = await pool.query(
      "select tiktok_publish_id from claim where id = $1", [claim.id]);
    expect(stored.tiktok_publish_id).toBe(publishId);

    // still encoding on TikTok's side
    const pending = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/direct-post/status`, headers: clipper.h });
    expect(pending.json()).toEqual({ state: "processing" });

    // TikTok publishes and links the audio to the contract's sound
    tiktok.completePublish(publishId, {
      videoId: "dp_video_1", authorOpenId: "oid_dp_clipper", musicId: "m_dp",
      isPublic: true, viewCount: 0, postedAt: new Date(),
    });
    const done = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/direct-post/status`, headers: clipper.h });
    expect(done.json().state).toBe("posted");
    expect(done.json().submission.state).toBe("counting");
    expect(done.json().checks).toMatchObject({
      sound_match: true, handle_verified: true, posted_in_window: true,
      duplicate_clear: true, direct_post: true,
    });

    const { rows: [sub] } = await pool.query(
      "select tiktok_video_id, state from submission where claim_id = $1", [claim.id]);
    expect(sub).toMatchObject({ tiktok_video_id: "dp_video_1", state: "counting" });
  });

  it("accepts a post the Display API hasn't indexed yet, and lets counting guard the sound", async () => {
    config.directPostEnabled = true;
    const { clipper, claim } = await claimReady();
    const start = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/direct-post`,
      headers: { ...clipper.h, ...idem() },
      payload: { caption: "x", privacyLevel: "PUBLIC_TO_EVERYONE", videoSizeBytes: 2_000 },
    });
    // live on TikTok, not yet readable through the Display API
    tiktok.completePublish(start.json().publishId, {
      videoId: "dp_lagging", authorOpenId: "oid_dp_clipper", musicId: "m_dp",
      isPublic: true, viewCount: 0, postedAt: new Date(),
    }, { indexed: false });

    const done = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/direct-post/status`, headers: clipper.h });
    expect(done.json().submission.state).toBe("counting");
    // provenance is certain even though the sound can't be read yet
    expect(done.json().checks).toMatchObject({
      sound_match: null, handle_verified: true, posted_in_window: true, direct_post: true,
    });

    // when it does index with the wrong audio, the counting job refuses to pay
    const { rows: [sub] } = await pool.query(
      "select id from submission where claim_id = $1", [claim.id]);
    tiktok.seedVideo({
      videoId: "dp_lagging", authorOpenId: "oid_dp_clipper", musicId: "some_other_audio",
      isPublic: true, viewCount: 500_000, postedAt: new Date(),
    });
    await app.services.counting.pollSubmission(sub.id);
    const { balance, refs } = await import("../src/domain/ledger.js");
    expect(await balance(pool, refs.held(sub.id))).toBe(0);
    const { rows: [sample] } = await pool.query(
      "select anomaly_flags from view_sample where submission_id = $1", [sub.id]);
    expect(sample.anomaly_flags).toContain("music_mismatch");
  });

  it("surfaces a failed publish and clears the in-flight id", async () => {
    config.directPostEnabled = true;
    const { clipper, claim } = await claimReady();
    const start = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/direct-post`,
      headers: { ...clipper.h, ...idem() },
      payload: { caption: "x", privacyLevel: "SELF_ONLY", videoSizeBytes: 1_000 },
    });
    tiktok.failPublish(start.json().publishId, "video_too_long");

    const res = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/direct-post/status`, headers: clipper.h });
    expect(res.statusCode).toBe(422);
    expect(res.json().message).toContain("video_too_long");
    const { rows: [claimRow] } = await pool.query(
      "select tiktok_publish_id from claim where id = $1", [claim.id]);
    expect(claimRow.tiktok_publish_id).toBeNull();
  });

  // Rule 01 on the Terms panel: a re-upload of the audio does not count.
  // Posting through the app doesn't buy an exemption — the clipper finds out
  // at lodge time instead of after two weeks of unpaid views.
  it("rejects a post whose audio isn't the contract's sound", async () => {
    config.directPostEnabled = true;
    const { clipper, claim } = await claimReady();
    const start = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/direct-post`,
      headers: { ...clipper.h, ...idem() },
      payload: { caption: "x", privacyLevel: "PUBLIC_TO_EVERYONE", videoSizeBytes: 2_000 },
    });
    tiktok.completePublish(start.json().publishId, {
      videoId: "dp_video_2", authorOpenId: "oid_dp_clipper", musicId: "some_other_audio",
      isPublic: true, viewCount: 0, postedAt: new Date(),
    });
    const done = await app.inject({
      method: "POST", url: `/v1/claims/${claim.id}/direct-post/status`, headers: clipper.h });
    expect(done.json().submission.state).toBe("rejected");
    expect(done.json().checks.sound_match).toBe(false);
  });
});
