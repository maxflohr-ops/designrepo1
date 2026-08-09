import type pg from "pg";
import { pool, withTxn } from "../../db.js";
import { config } from "../../config.js";
import { transition } from "../../domain/states.js";
import {
  balance, clearToPayable, fundPurse, maxClipperAmountFor, platformFee, refs, releaseReserve, reserveAccrual,
} from "../../domain/ledger.js";
import type { StripeGateway } from "../../gateways/stripe.js";
import type { TikTokClient } from "../../gateways/tiktok.js";
import { pushWire } from "../notify/service.js";

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export interface BountyDraft {
  soundId: string;
  title: string;
  brief: string;
  payoutModel: "per_view" | "per_clip";
  rateCents: number;
  rateUnit: number; // views per rateCents for per_view; ignored for per_clip
  purseCents: number;
  slotCap: number;
  deadlineAt: Date;
  platform?: string;
}

export class BountyService {
  constructor(private stripe: StripeGateway, private tiktok: TikTokClient) {}

  // POST /v1/bounties — artist draft; returns the PaymentIntent client secret.
  async createDraft(artistId: string, d: BountyDraft) {
    const platform = d.platform ?? "tiktok";
    const windowDays = config.countingWindowDays[platform];
    if (windowDays === undefined)
      throw new ApiError(422, "platform_unsupported", `${platform} counting is not available yet`); // §8 Q3
    return withTxn(async (c) => {
      const { rows: [bounty] } = await c.query(
        `insert into bounty (sound_id, artist_account_id, title, brief, payout_model, rate_cents,
                             rate_unit, purse_cents, slot_cap, window_days, platform, deadline_at)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) returning *`,
        [d.soundId, artistId, d.title, d.brief, d.payoutModel, d.rateCents,
         d.payoutModel === "per_view" ? d.rateUnit : 1, d.purseCents, d.slotCap,
         windowDays, platform, d.deadlineAt],
      );
      const intent = await this.stripe.createPaymentIntent(d.purseCents, { bountyId: bounty.id });
      await c.query("update bounty set stripe_payment_intent_id = $2 where id = $1", [bounty.id, intent.id]);
      await transition(c, "bounty", bounty.id, "funding");
      return { bounty: { ...bounty, state: "funding" }, clientSecret: intent.clientSecret };
    });
  }

  // Stripe webhook: payment_intent.succeeded → escrow credited, bounty live.
  async markFunded(paymentIntentId: string, amountCents: number) {
    return withTxn(async (c) => {
      const { rows: [b] } = await c.query(
        "select * from bounty where stripe_payment_intent_id = $1 for update", [paymentIntentId],
      );
      if (!b) throw new ApiError(404, "unknown_payment", "no bounty for that payment intent");
      if (b.state === "funding") {
        await fundPurse(c, b.id, b.artist_account_id, amountCents);
        await transition(c, "bounty", b.id, "live");
      }
      // top-up against an already-live bounty: a new escrow deposit, no state change (§4)
      else if (b.state === "live" || b.state === "closing") {
        await fundPurse(c, b.id, b.artist_account_id, amountCents);
        await c.query("update bounty set purse_cents = purse_cents + $2, updated_at = now() where id = $1",
          [b.id, amountCents]);
        if (b.state === "closing") await transition(c, "bounty", b.id, "live");
      }
      return b.id;
    });
  }

  // Top up an existing purse: new PaymentIntent against the same bounty.
  async createTopUp(artistId: string, bountyId: string, amountCents: number) {
    const { rows: [b] } = await pool.query(
      "select * from bounty where id = $1", [bountyId]);
    if (!b) throw new ApiError(404, "not_found", "bounty not found");
    if (b.artist_account_id !== artistId) throw new ApiError(403, "not_owner", "not your bounty");
    if (!["live", "closing"].includes(b.state))
      throw new ApiError(409, "bad_state", `cannot top up a ${b.state} bounty`);
    const intent = await this.stripe.createPaymentIntent(amountCents, { bountyId, topUp: "1" });
    await pool.query(
      "update bounty set stripe_payment_intent_id = $2 where id = $1", [bountyId, intent.id]);
    return { clientSecret: intent.clientSecret };
  }

  // POST /v1/bounties/:id/claims — Seize it. Atomic slot decrement; 409 at cap.
  async claim(accountId: string, bountyId: string) {
    // §7 — TikTok account age and follower floor apply at claim time, not signup.
    const { rows: [acct] } = await pool.query(
      "select * from account where id = $1", [accountId]);
    if (!acct) throw new ApiError(401, "unauthenticated", "no account");
    if (acct.suspended_at) throw new ApiError(403, "suspended", "account suspended");
    const profile = await this.tiktok.getProfile(acct.tiktok_open_id);
    if (!profile || profile.accountAgeDays < config.claimMinAccountAgeDays
        || profile.followerCount < config.claimMinFollowers)
      throw new ApiError(403, "account_floor", "TikTok account too new or too small to claim");

    return withTxn(async (c) => {
      const { rows: [b] } = await c.query("select * from bounty where id = $1 for update", [bountyId]);
      if (!b) throw new ApiError(404, "not_found", "bounty not found");
      if (b.state !== "live") throw new ApiError(409, "not_live", `bounty is ${b.state}`);
      if (new Date(b.deadline_at) < new Date()) throw new ApiError(409, "past_deadline", "deadline passed");
      const { rows: [{ n }] } = await c.query(
        "select count(*)::int as n from claim where bounty_id = $1 and state in ('open','submitted')", [bountyId]);
      if (n >= b.slot_cap) throw new ApiError(409, "slots_full", "the cap is met");
      const { rows: [claim] } = await c.query(
        `insert into claim (bounty_id, account_id, expires_at)
         values ($1, $2, now() + make_interval(days => $3)) returning *`,
        [bountyId, accountId, config.claimWindowDays],
      ).catch((e: unknown) => {
        if ((e as { code?: string }).code === "23505")
          throw new ApiError(409, "already_claimed", "you already hold a claim on this bounty");
        throw e;
      });
      return claim;
    });
  }

  // PATCH /v1/claims/:id — checklist. Client-owned, server-validated shape.
  async patchChecklist(accountId: string, claimId: string, checklist: unknown) {
    if (!Array.isArray(checklist) || checklist.length !== 4 || checklist.some((x) => typeof x !== "boolean"))
      throw new ApiError(422, "bad_checklist", "checklist must be four booleans");
    const { rowCount, rows } = await pool.query(
      `update claim set checklist = $3 where id = $1 and account_id = $2 and state = 'open' returning *`,
      [claimId, accountId, JSON.stringify(checklist)],
    );
    if (!rowCount) throw new ApiError(404, "not_found", "no open claim");
    return rows[0];
  }

  // POST /v1/claims/:id/submission — lodge the link; the four checks run synchronously.
  async createSubmission(accountId: string, claimId: string, tiktokVideoId: string) {
    const { rows: [claimRow] } = await pool.query(
      `select claim.*, bounty.sound_id, bounty.platform, bounty.window_days, bounty.state as bounty_state,
              bounty.payout_model, bounty.rate_cents, bounty.id as b_id
       from claim join bounty on bounty.id = claim.bounty_id where claim.id = $1`, [claimId]);
    if (!claimRow || claimRow.account_id !== accountId) throw new ApiError(404, "not_found", "claim not found");
    if (claimRow.state !== "open") throw new ApiError(409, "bad_state", `claim is ${claimRow.state}`);

    const { rows: [acct] } = await pool.query(
      "select * from account where id = $1", [accountId]);
    const { rows: [sound] } = await pool.query(
      "select * from sound where id = $1", [claimRow.sound_id]);
    const video = await this.tiktok.getVideo(tiktokVideoId);

    // The four automatic checks (Submit screen §2).
    const checks = {
      sound_match: !!video && video.musicId === sound.tiktok_music_id,
      posted_in_window: !!video && video.postedAt >= new Date(claimRow.claimed_at)
        && video.postedAt <= new Date(claimRow.expires_at),
      handle_verified: !!video && video.authorOpenId === acct.tiktok_open_id,
      duplicate_clear: true,
    };
    const { rows: [dupe] } = await pool.query(
      "select 1 from submission where tiktok_video_id = $1 and state not in ('void','rejected')", [tiktokVideoId]);
    if (dupe) checks.duplicate_clear = false;

    const passed = Object.values(checks).every(Boolean);
    return withTxn(async (c) => {
      const windowEnds = new Date(video ? video.postedAt : new Date());
      windowEnds.setDate(windowEnds.getDate() + claimRow.window_days);
      const { rows: [sub] } = await c.query(
        `insert into submission (claim_id, tiktok_video_id, posted_at, window_ends_at, checks, next_poll_at)
         values ($1,$2,$3,$4,$5, now()) returning *`,
        [claimId, tiktokVideoId, video?.postedAt ?? new Date(), windowEnds, JSON.stringify(checks)],
      );
      if (!passed) {
        await transition(c, "submission", sub.id, "rejected");
        return { submission: { ...sub, state: "rejected" }, checks };
      }
      await transition(c, "submission", sub.id, "counting");
      await transition(c, "claim", claimId, "submitted");
      // per-clip contracts reserve the whole rate up front so first posted is first paid
      if (claimRow.payout_model === "per_clip") {
        await this.reserveCapped(c, claimRow.b_id, sub.id, accountId, claimRow.rate_cents);
      }
      return { submission: { ...sub, state: "counting" }, checks };
    });
  }

  // The §4 invariant lives here: reserves + paid-out never exceed the funded
  // total, enforced inside the same transaction as the reserve write. The
  // bounty row lock serialises concurrent accruals; the escrow balance is
  // derived from the ledger under that lock. Returns the amount actually
  // reserved (clipper portion), which may be capped.
  async reserveCapped(
    c: pg.PoolClient, bountyId: string, submissionId: string, accountId: string, clipperWantCents: number,
  ): Promise<number> {
    const { rows: [b] } = await c.query(
      "select state, purse_cents, artist_account_id from bounty where id = $1 for update", [bountyId]);
    if (!["live", "closing"].includes(b.state)) return 0;

    const remaining = await balance(c, refs.escrow(bountyId));
    let grant = Math.min(clipperWantCents, maxClipperAmountFor(remaining));

    // §7 — cap one account's share of a single purse.
    const shareCap = Math.floor((Number(b.purse_cents) * config.maxPurseShareBps) / 10000);
    const { rows: [{ mine }] } = await c.query(
      `select coalesce(sum(le.amount_cents), 0)::bigint as mine
       from ledger_entry le
       join submission s on s.id = le.submission_id
       join claim cl on cl.id = s.claim_id
       where le.bounty_id = $1 and cl.account_id = $2
         and le.direction = 'credit' and le.account_ref like 'held:%'`,
      [bountyId, accountId],
    );
    grant = Math.min(grant, Math.max(shareCap - Number(mine), 0));
    if (grant <= 0) {
      if (remaining < clipperWantCents + platformFee(clipperWantCents) && b.state === "live")
        await transition(c, "bounty", bountyId, "closing");
      return 0;
    }
    await reserveAccrual(c, bountyId, submissionId, grant);
    // if the purse can no longer cover another cent, the board should stop showing it
    const left = await balance(c, refs.escrow(bountyId));
    if (grant < clipperWantCents || maxClipperAmountFor(left) === 0) {
      if (b.state === "live") await transition(c, "bounty", bountyId, "closing");
    }
    await c.query("update submission set accrued_cents = accrued_cents + $2 where id = $1",
      [submissionId, grant]);
    return grant;
  }

  // POST /v1/submissions/:id/verdict — approve is a payout intent, not a state flag.
  async verdict(artistId: string, submissionId: string, verdict: "approve" | "dispute", reason?: string) {
    return withTxn(async (c) => {
      const { rows: [sub] } = await c.query(
        `select s.*, cl.account_id as clipper_id, cl.id as claim_id, b.id as bounty_id,
                b.artist_account_id, b.title as bounty_title
         from submission s join claim cl on cl.id = s.claim_id join bounty b on b.id = cl.bounty_id
         where s.id = $1 for update of s`, [submissionId]);
      if (!sub) throw new ApiError(404, "not_found", "submission not found");
      if (sub.artist_account_id !== artistId) throw new ApiError(403, "not_owner", "not your bounty");

      if (verdict === "approve") {
        if (!["counting", "payable", "held"].includes(sub.state))
          throw new ApiError(409, "bad_state", `submission is ${sub.state}`);
        if (sub.state !== "payable") await transition(c, "submission", submissionId, "payable");
        const { paid } = await clearToPayable(c, sub.bounty_id, submissionId, sub.clipper_id);
        await transition(c, "submission", submissionId, "paid");
        await transition(c, "claim", sub.claim_id, "settled");
        await pushWire(c, sub.clipper_id, `Your clip cleared. $${(paid / 100).toLocaleString()} is payable.`, "money");
        return { state: "paid", paidCents: paid };
      }

      // dispute: hold the reserve. §8 Q2 — the reserve keeps counting against
      // the purse; nothing is fronted and nothing releases until resolution.
      if (!["counting", "payable"].includes(sub.state))
        throw new ApiError(409, "bad_state", `submission is ${sub.state}`);
      await transition(c, "submission", submissionId, "held", ", held_reason = $3", [reason ?? "artist_dispute"]);
      const { rows: [d] } = await c.query(
        `insert into dispute (submission_id, opened_by, reason_code) values ($1,$2,$3) returning *`,
        [submissionId, artistId, reason ?? "artist_dispute"]);
      await pushWire(c, sub.clipper_id,
        `Held for review on “${sub.bounty_title}” — you have ${config.appealSlaHours} hours to appeal.`, "warn");
      return { state: "held", disputeId: d.id };
    });
  }

  // POST /v1/disputes/:id/appeal — the 72-hour SLA clock starts here.
  async appeal(clipperId: string, disputeId: string, statement: string, evidence: unknown[]) {
    return withTxn(async (c) => {
      const { rows: [d] } = await c.query(
        `select d.*, s.claim_id, cl.account_id as clipper_id, b.artist_account_id, b.id as bounty_id
         from dispute d join submission s on s.id = d.submission_id
         join claim cl on cl.id = s.claim_id join bounty b on b.id = cl.bounty_id
         where d.id = $1 for update of d`, [disputeId]);
      if (!d || d.clipper_id !== clipperId) throw new ApiError(404, "not_found", "dispute not found");
      if (d.state !== "open") throw new ApiError(409, "bad_state", `dispute is ${d.state}`);
      await c.query(
        `update dispute set state = 'appealed', appeal_statement = $2, evidence = $3,
                appeal_deadline = now() + make_interval(hours => $4) where id = $1`,
        [disputeId, statement, JSON.stringify(evidence), config.appealSlaHours]);

      // §7 — artists who dispute everything auto-lose above the threshold.
      const { rows: [{ total, disputed }] } = await c.query(
        `select count(*)::int as total,
                count(*) filter (where d2.id is not null)::int as disputed
         from submission s2
         join claim cl2 on cl2.id = s2.claim_id
         join bounty b2 on b2.id = cl2.bounty_id
         left join dispute d2 on d2.submission_id = s2.id and d2.opened_by = $1
         where b2.artist_account_id = $1 and s2.state in ('paid','held','void')`,
        [d.artist_account_id]);
      if (total >= config.artistAutoResolveMinVerdicts
          && disputed / total > config.artistAutoResolveDisputeRate) {
        await this.resolveDisputeLocked(c, d, "clipper");
        return { state: "resolved", resolution: "clipper", autoResolved: true };
      }
      return { state: "appealed", slaHours: config.appealSlaHours };
    });
  }

  // staff resolution (or auto-resolution). clipper wins → reserve clears to
  // payable; artist wins → reserve releases back to the purse.
  async resolveDispute(disputeId: string, resolution: "clipper" | "artist") {
    return withTxn(async (c) => {
      const { rows: [d] } = await c.query(
        `select d.*, s.claim_id, cl.account_id as clipper_id, b.id as bounty_id
         from dispute d join submission s on s.id = d.submission_id
         join claim cl on cl.id = s.claim_id join bounty b on b.id = cl.bounty_id
         where d.id = $1 for update of d`, [disputeId]);
      if (!d) throw new ApiError(404, "not_found", "dispute not found");
      return this.resolveDisputeLocked(c, d, resolution);
    });
  }

  private async resolveDisputeLocked(
    c: pg.PoolClient,
    d: { id: string; submission_id: string; bounty_id: string; clipper_id: string; claim_id: string; state: string },
    resolution: "clipper" | "artist",
  ) {
    if (d.state === "resolved") throw new ApiError(409, "bad_state", "already resolved");
    if (resolution === "clipper") {
      await transition(c, "submission", d.submission_id, "payable");
      const { paid } = await clearToPayable(c, d.bounty_id, d.submission_id, d.clipper_id);
      await transition(c, "submission", d.submission_id, "paid");
      await transition(c, "claim", d.claim_id, "settled");
      await pushWire(c, d.clipper_id, `Appeal upheld. $${(paid / 100).toLocaleString()} is payable.`, "money");
    } else {
      await releaseReserve(c, d.bounty_id, d.submission_id);
      await transition(c, "submission", d.submission_id, "void");
      await transition(c, "claim", d.claim_id, "settled");
      await c.query("update submission set accrued_cents = 0 where id = $1", [d.submission_id]);
      await pushWire(c, d.clipper_id, "Appeal denied. The hold was released back to the purse.", "warn");
    }
    await c.query(
      "update dispute set state = 'resolved', resolved_at = now(), resolution = $2 where id = $1",
      [d.id, resolution]);
    return { state: "resolved", resolution };
  }
}
