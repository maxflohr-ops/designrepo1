import { beforeEach, describe, expect, it } from "vitest";
import {
  fundedBountyWithSubmission, goodProfile, mkAccount, mkSound, pool, resetDb, services,
} from "./helpers.js";
import { balance, platformFee, refs } from "../src/domain/ledger.js";
import { expireClaims } from "../src/modules/treasury/service.js";
import { config } from "../src/config.js";

const state = async (table: string, id: string) =>
  (await pool.query(`select state from ${table} where id = $1`, [id])).rows[0].state;

describe("bounty lifecycle", () => {
  beforeEach(resetDb);

  it("funds → claims → submits → counts → accrues at the advertised rate", async () => {
    const { svc, bounty, submission } = await fundedBountyWithSubmission({ views: 0 });
    svc.tiktok.videos.get("v1")!.viewCount = 50_000;
    const r = await svc.counting.pollSubmission(submission.id);
    // $5 per 5,000 views on 50k = $50 clipper, $5 fee grossed from the purse
    expect(r).toMatchObject({ reserved: 5_000 });
    expect(await balance(pool, refs.held(submission.id))).toBe(5_000);
    expect(await balance(pool, refs.escrow(bounty.id))).toBe(50_000 - 5_000 - 500);
    expect(await state("submission", submission.id)).toBe("counting");
  });

  it("enforces the purse invariant inside the accrual transaction — first posted, first paid", async () => {
    // $500 purse, three clippers all going viral. Reserves + fees can never
    // exceed the funded total; the last accrual stops at the remaining balance
    // and the bounty moves to closing.
    const { svc, bounty, submission } = await fundedBountyWithSubmission({ purseCents: 50_000 });
    const subs = [submission.id];
    for (let i = 0; i < 2; i++) {
      const acct = await mkAccount(`viral${i}`);
      goodProfile(svc.tiktok, acct.tiktok_open_id, `viral${i}`);
      const cl = await svc.bounties.claim(acct.id, bounty.id);
      svc.tiktok.seedVideo({
        videoId: `vv${i}`, authorOpenId: acct.tiktok_open_id, musicId: "m_ridge",
        isPublic: true, viewCount: 0, postedAt: new Date(),
      });
      const { submission: s } = await svc.bounties.createSubmission(acct.id, cl.id, `vv${i}`);
      subs.push(s.id);
    }
    svc.tiktok.videos.get("v1")!.viewCount = 5_000_000;
    svc.tiktok.videos.get("vv0")!.viewCount = 5_000_000;
    svc.tiktok.videos.get("vv1")!.viewCount = 5_000_000;
    for (const id of subs) await svc.counting.pollSubmission(id);

    const escrow = await balance(pool, refs.escrow(bounty.id));
    let held = 0, fees = 0;
    for (const id of subs) {
      held += await balance(pool, refs.held(id));
      fees += await balance(pool, refs.heldFee(id));
    }
    expect(escrow).toBeGreaterThanOrEqual(0);
    expect(held + fees + escrow).toBe(50_000); // nothing minted, nothing lost
    // first two hit the §7 share cap ($200 each), the third drains what's left
    expect(await balance(pool, refs.held(subs[0]!))).toBe(20_000);
    expect(await balance(pool, refs.held(subs[1]!))).toBe(20_000);
    expect(await balance(pool, refs.held(subs[2]!))).toBe(5_455);
    expect(escrow).toBe(0);
    expect(await state("bounty", bounty.id)).toBe("closing");
  });

  it("spike deltas reserve but hold the submission for a human", async () => {
    const { svc, submission } = await fundedBountyWithSubmission({ purseCents: 5_000_000 });
    svc.tiktok.videos.get("v1")!.viewCount = config.spikeAbsoluteFloor + 1;
    await svc.counting.pollSubmission(submission.id);
    expect(await state("submission", submission.id)).toBe("held");
    expect(await balance(pool, refs.held(submission.id))).toBeGreaterThan(0);
    const { rows: [sample] } = await pool.query(
      "select anomaly_flags from view_sample where submission_id = $1 order by id desc limit 1", [submission.id]);
    expect(sample.anomaly_flags).toContain("spike");
  });

  it("negative deltas are recorded but never accrue", async () => {
    const { svc, submission } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 10_000;
    await svc.counting.pollSubmission(submission.id, new Date(Date.now() + 1000));
    svc.tiktok.videos.get("v1")!.viewCount = 4_000; // count went down
    await svc.counting.pollSubmission(submission.id, new Date(Date.now() + 2000));
    const { rows } = await pool.query(
      "select delta, anomaly_flags from view_sample where submission_id = $1 order by id", [submission.id]);
    expect(rows[1].delta).toBe(-6000);
    expect(rows[1].anomaly_flags).toContain("negative_delta");
    expect(await balance(pool, refs.held(submission.id))).toBe(1_000); // still $10 from 10k views
  });

  it("a deleted video voids the submission and releases its reserve", async () => {
    const { svc, bounty, submission, claim } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 20_000;
    await svc.counting.pollSubmission(submission.id, new Date(Date.now() + 1000));
    expect(await balance(pool, refs.held(submission.id))).toBe(2_000);
    svc.tiktok.videos.delete("v1");
    await svc.counting.pollSubmission(submission.id, new Date(Date.now() + 2000));
    expect(await state("submission", submission.id)).toBe("void");
    expect(await state("claim", claim.id)).toBe("settled");
    expect(await balance(pool, refs.held(submission.id))).toBe(0);
    expect(await balance(pool, refs.escrow(bounty.id))).toBe(50_000);
  });

  it("music_id swap stops the count without voiding", async () => {
    const { svc, submission } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 10_000;
    await svc.counting.pollSubmission(submission.id, new Date(Date.now() + 1000));
    const v = svc.tiktok.videos.get("v1")!;
    v.musicId = "other_sound"; v.viewCount = 90_000;
    await svc.counting.pollSubmission(submission.id, new Date(Date.now() + 2000));
    expect(await balance(pool, refs.held(submission.id))).toBe(1_000); // only the first 10k counted
    expect(await state("submission", submission.id)).toBe("counting");
  });

  it("artist approve is a payout intent: reserve clears to payable, claim settles", async () => {
    const { svc, artist, clipper, submission, claim } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 88_000;
    await svc.counting.pollSubmission(submission.id);
    const out = await svc.bounties.verdict(artist.id, submission.id, "approve");
    expect(out).toMatchObject({ state: "paid", paidCents: 8_800 });
    expect(await balance(pool, refs.payable(clipper.id))).toBe(8_800);
    expect(await balance(pool, refs.fees)).toBe(platformFee(8_800));
    expect(await state("claim", claim.id)).toBe("settled");
  });

  it("dispute holds the reserve against the purse; appeal loss releases it, win pays it", async () => {
    const { svc, artist, clipper, submission } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 88_000;
    await svc.counting.pollSubmission(submission.id);

    const d = await svc.bounties.verdict(artist.id, submission.id, "dispute", "sound_mismatch");
    expect(await state("submission", submission.id)).toBe("held");
    // §8 Q2 — the reserve still counts against the purse while held
    expect(await balance(pool, refs.held(submission.id))).toBe(8_800);

    const appeal = await svc.bounties.appeal(clipper.id, (d as { disputeId: string }).disputeId,
      "TikTok relinked the sound after a rename.", [{ kind: "screen_recording" }]);
    expect(appeal.state).toBe("appealed");

    await svc.bounties.resolveDispute((d as { disputeId: string }).disputeId, "clipper");
    expect(await state("submission", submission.id)).toBe("paid");
    expect(await balance(pool, refs.payable(clipper.id))).toBe(8_800);
  });

  it("an artist above the dispute-rate threshold auto-loses appeals (§7)", async () => {
    const { svc, artist, clipper, bounty } = await fundedBountyWithSubmission({ purseCents: 500_000 });
    // build 6 disputed submissions from separate clippers
    let lastDispute = "";
    for (let i = 0; i < 6; i++) {
      const other = await mkAccount(`clip${i}`);
      goodProfile(svc.tiktok, other.tiktok_open_id, `clip${i}`);
      const cl = await svc.bounties.claim(other.id, bounty.id);
      svc.tiktok.seedVideo({
        videoId: `vx${i}`, authorOpenId: other.tiktok_open_id, musicId: "m_ridge",
        isPublic: true, viewCount: 10_000, postedAt: new Date(),
      });
      const { submission: s } = await svc.bounties.createSubmission(other.id, cl.id, `vx${i}`);
      await svc.counting.pollSubmission(s.id);
      const v = await svc.bounties.verdict(artist.id, s.id, "dispute", "vibes");
      lastDispute = (v as { disputeId: string }).disputeId;
      if (i < 5) await svc.bounties.resolveDispute(lastDispute, "artist");
    }
    const { rows: [d] } = await pool.query("select * from dispute where id = $1", [lastDispute]);
    const { rows: [sub] } = await pool.query(
      "select claim_id from submission where id = $1", [d.submission_id]);
    const { rows: [cl] } = await pool.query("select account_id from claim where id = $1", [sub.claim_id]);
    const result = await svc.bounties.appeal(cl.account_id, lastDispute, "obviously fine", []);
    expect(result).toMatchObject({ state: "resolved", resolution: "clipper", autoResolved: true });
  });

  it("settlement refunds exactly the unspent purse — fee only on the spent portion (§8 Q1)", async () => {
    const { svc, artist, submission, bounty } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 100_000; // $100 + $10 fee spent
    await svc.counting.pollSubmission(submission.id);
    await svc.bounties.verdict(artist.id, submission.id, "approve");

    const { refundedCents } = await svc.treasury.settleBounty(bounty.id);
    expect(refundedCents).toBe(50_000 - 10_000 - 1_000);
    expect(await state("bounty", bounty.id)).toBe("settled");
    expect(svc.stripe.refunds[0]).toMatchObject({ amountCents: refundedCents });
    // an unclaimed purse costs the artist nothing: fee was never taken at funding
    expect(await balance(pool, refs.fees)).toBe(1_000);
  });

  it("chargeback freezes the bounty, suspends the artist, books the spent portion as debt (§8 Q4)", async () => {
    const { svc, artist, clipper, submission, bounty, intentId } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 100_000;
    await svc.counting.pollSubmission(submission.id);
    await svc.bounties.verdict(artist.id, submission.id, "approve");

    const { debtCents } = await svc.treasury.handleChargeback(intentId, 50_000);
    expect(debtCents).toBe(11_000);
    expect(await state("bounty", bounty.id)).toBe("frozen");
    const { rows: [a] } = await pool.query("select suspended_at from account where id = $1", [artist.id]);
    expect(a.suspended_at).not.toBeNull();
    expect(await balance(pool, refs.payable(clipper.id))).toBe(10_000); // clipper keeps it
  });

  it("claim expiry returns the slot and is job-driven", async () => {
    const { svc, bounty } = await fundedBountyWithSubmission();
    const other = await mkAccount("latecomer");
    goodProfile(svc.tiktok, other.tiktok_open_id, "latecomer");
    const cl = await svc.bounties.claim(other.id, bounty.id);
    await pool.query("update claim set expires_at = now() - interval '1 hour' where id = $1", [cl.id]);
    const n = await expireClaims();
    expect(n).toBe(1);
    expect(await state("claim", cl.id)).toBe("expired");
  });

  it("slot cap 409s atomically and double-claims are rejected", async () => {
    const svcs = services();
    const artist = await mkAccount("artist2", ["artist"]);
    const sound = await mkSound("m_two", "Two", artist.id);
    const { bounty, clientSecret } = await svcs.bounties.createDraft(artist.id, {
      soundId: sound.id, title: "t", brief: "", payoutModel: "per_clip", rateCents: 2000,
      rateUnit: 1, purseCents: 40_000, slotCap: 1,
      deadlineAt: new Date(Date.now() + 86400_000),
    });
    await svcs.bounties.markFunded(clientSecret.replace(/_secret_test$/, ""), 40_000);
    const c1 = await mkAccount("c1"); const c2 = await mkAccount("c2");
    goodProfile(svcs.tiktok, c1.tiktok_open_id, "c1");
    goodProfile(svcs.tiktok, c2.tiktok_open_id, "c2");
    await svcs.bounties.claim(c1.id, bounty.id);
    await expect(svcs.bounties.claim(c1.id, bounty.id)).rejects.toMatchObject({ status: 409 });
    await expect(svcs.bounties.claim(c2.id, bounty.id)).rejects.toMatchObject({ code: "slots_full" });
  });

  it("per-clip contracts reserve the full rate at submission — first posted, first paid", async () => {
    const { svc, bounty, submission } = await fundedBountyWithSubmission({
      payoutModel: "per_clip", rateCents: 2_000, purseCents: 10_000,
    });
    // rate $20 + $2 fee reserved up front from a $100 purse
    expect(await balance(pool, refs.held(submission.id))).toBe(2_000);
    expect(await balance(pool, refs.escrow(bounty.id))).toBe(10_000 - 2_200);
  });

  it("first payout of a new account holds 7 days past settlement (§7)", async () => {
    const { svc, artist, clipper, submission } = await fundedBountyWithSubmission();
    svc.tiktok.videos.get("v1")!.viewCount = 50_000;
    await svc.counting.pollSubmission(submission.id);
    await svc.bounties.verdict(artist.id, submission.id, "approve");
    await expect(svc.treasury.createPayout(clipper.id, 5_000))
      .rejects.toMatchObject({ code: "first_payout_hold" });
    // age the clearance and it goes through (rule dropped only to backdate test data)
    await pool.query("drop rule ledger_no_update on ledger_entry");
    await pool.query(
      "update ledger_entry set created_at = created_at - interval '8 days' where kind = 'payout_clear'");
    await pool.query(
      "create rule ledger_no_update as on update to ledger_entry do instead nothing");
    const out = await svc.treasury.createPayout(clipper.id, 5_000);
    expect(out.amountCents).toBe(5_000);
    expect(svc.stripe.transfers).toHaveLength(1);
    expect(await balance(pool, refs.payable(clipper.id))).toBe(0);
  });

  it("caps one account's share of a purse (§7)", async () => {
    const { svc, submission, bounty } = await fundedBountyWithSubmission({ purseCents: 100_000 });
    svc.tiktok.videos.get("v1")!.viewCount = 5_000_000; // wants $5,000 from a $1,000 purse
    await svc.counting.pollSubmission(submission.id);
    // 40% share cap of $1,000 = $400, tighter than the escrow cap here
    expect(await balance(pool, refs.held(submission.id))).toBe(40_000);
  });
});
