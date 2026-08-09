import { pool, withTxn } from "../../db.js";
import { redis } from "../../redis.js";
import { config } from "../../config.js";
import { transition } from "../../domain/states.js";
import { releaseReserve } from "../../domain/ledger.js";
import type { TikTokClient } from "../../gateways/tiktok.js";
import type { BountyService } from "../bounties/service.js";
import { pushWire } from "../notify/service.js";

// §5 — the decaying cadence, in minutes: hourly for the first 48 hours, every
// six hours to day 7, daily to day 14.
export function cadenceMinutes(postedAt: Date, now: Date): number | null {
  const hours = (now.getTime() - postedAt.getTime()) / 3_600_000;
  if (hours < 48) return 60;
  if (hours < 24 * 7) return 360;
  if (hours < 24 * 14) return 1440;
  return null; // window over
}

const nextTier = (m: number) => (m === 60 ? 360 : 1440);

// Deterministic per-submission stagger so an artist's submissions spread
// across the hour instead of thundering together.
function staggerSeconds(submissionId: string): number {
  let h = 0;
  for (const ch of submissionId) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return h % 1800;
}

export class CountingService {
  constructor(private tiktok: TikTokClient, private bounties: BountyService) {}

  // One scheduler pass: poll every due submission, respecting the poll budget.
  // When the budget runs out we degrade to the next tier's cadence rather than
  // dropping the sample, and mark the submission so the *next* sample records
  // the degradation (§5: "record the degradation on the sample").
  async runOnce(now = new Date()) {
    const { rows: due } = await pool.query(
      `select s.id, s.posted_at, b.artist_account_id
       from submission s
       join claim cl on cl.id = s.claim_id
       join bounty b on b.id = cl.bounty_id
       where s.state in ('counting','held') and s.next_poll_at <= $1
       order by b.artist_account_id, s.next_poll_at`,
      [now],
    );
    let budget = config.pollBudgetPerRun;
    const results = [];
    for (const row of due) {
      if (budget <= 0) {
        const tier = cadenceMinutes(new Date(row.posted_at), now) ?? 1440;
        await pool.query(
          `update submission set next_poll_at = $2::timestamptz + make_interval(mins => $3), degrade_next = true
           where id = $1`,
          [row.id, now, nextTier(tier)],
        );
        continue;
      }
      budget--;
      results.push(await this.pollSubmission(row.id, now));
    }
    return results;
  }

  // Poll one submission: write the append-only sample, apply the §5 rules,
  // accrue inside the same transaction as the reserve write (§4 invariant).
  async pollSubmission(submissionId: string, now = new Date()) {
    return withTxn(async (c) => {
      const { rows: [sub] } = await c.query(
        `select s.*, cl.account_id as clipper_id, cl.id as claim_id,
                b.id as bounty_id, b.payout_model, b.rate_cents, b.rate_unit,
                b.title as bounty_title, snd.tiktok_music_id as contract_music_id
         from submission s
         join claim cl on cl.id = s.claim_id
         join bounty b on b.id = cl.bounty_id
         join sound snd on snd.id = b.sound_id
         where s.id = $1 for update of s`,
        [submissionId],
      );
      if (!sub || !["counting", "held"].includes(sub.state)) return { skipped: submissionId };

      const video = await this.tiktok.getVideo(sub.tiktok_video_id);
      const { rows: [last] } = await c.query(
        `select view_count from view_sample where submission_id = $1 order by sampled_at desc limit 1`,
        [submissionId],
      );
      const lastCount = last ? Number(last.view_count) : 0;

      // Deleted at any point before settlement → void, release the reserve.
      if (!video) {
        await c.query(
          `insert into view_sample (submission_id, sampled_at, view_count, delta, anomaly_flags)
           values ($1, $2, $3, 0, '{deleted}')`,
          [submissionId, now, lastCount],
        );
        if (sub.state === "held") {
          await c.query("update dispute set state='resolved', resolved_at=now(), resolution='artist' where submission_id=$1 and state<>'resolved'", [submissionId]);
        }
        await releaseReserve(c, sub.bounty_id, submissionId);
        await transition(c, "submission", submissionId, "void");
        await transition(c, "claim", sub.claim_id, "settled");
        await c.query("update submission set accrued_cents = 0, next_poll_at = null where id = $1", [submissionId]);
        await pushWire(c, sub.clipper_id, `Your post on “${sub.bounty_title}” was deleted — the claim is void.`, "warn");
        return { submissionId, voided: true };
      }

      const flags: string[] = [];
      if (sub.degrade_next) flags.push("degraded");
      const delta = video.viewCount - lastCount;
      let countable = Math.max(delta, 0); // negative deltas are recorded, never accrued

      // Still public, still carrying the contract's music_id — otherwise the
      // delta does not count.
      if (!video.isPublic) { flags.push("private"); countable = 0; }
      if (video.musicId !== sub.contract_music_id) { flags.push("music_mismatch"); countable = 0; }
      if (delta < 0) flags.push("negative_delta");

      // Spike detection: a single-interval delta above the account's rolling
      // p99 is reserved but not paid until a human clears it.
      let spiked = false;
      if (countable > 0) {
        const p99 = await this.accountP99(sub.clipper_id, submissionId);
        const threshold = p99 ?? config.spikeAbsoluteFloor;
        if (countable > threshold) { flags.push("spike"); spiked = true; }
      }

      await c.query(
        `insert into view_sample (submission_id, sampled_at, view_count, delta, anomaly_flags)
         values ($1, $2, $3, $4, $5)`,
        [submissionId, now, video.viewCount, delta, flags],
      );

      // Accrue for per-view contracts, capped by the escrow balance inside
      // this same transaction. Held submissions keep reserving (§8 Q2) but
      // never clear to payable while held.
      let reserved = 0;
      if (sub.payout_model === "per_view" && countable > 0) {
        const totalCountable = await this.totalCountableViews(c, submissionId);
        const owedTotal = Math.floor((totalCountable * sub.rate_cents) / sub.rate_unit);
        const want = owedTotal - Number(sub.accrued_cents);
        if (want > 0)
          reserved = await this.bounties.reserveCapped(c, sub.bounty_id, submissionId, sub.clipper_id, want);
      }

      if (spiked && sub.state === "counting") {
        await transition(c, "submission", submissionId, "held", ", held_reason = $3", ["spike"]);
      }

      // Schedule the next poll, or finish the window.
      const tier = cadenceMinutes(new Date(sub.posted_at), now);
      if (tier === null || now >= new Date(sub.window_ends_at)) {
        await c.query("update submission set next_poll_at = null, degrade_next = false where id = $1", [submissionId]);
        if (sub.state === "counting" && !spiked) {
          await transition(c, "submission", submissionId, "payable");
          await pushWire(c, sub.clipper_id,
            `Counting closed on “${sub.bounty_title}”. $${(Number(sub.accrued_cents) + reserved) / 100} cleared for approval.`,
            "money");
        }
      } else {
        await c.query(
          `update submission set degrade_next = false,
             next_poll_at = $2::timestamptz + make_interval(mins => $3, secs => $4) where id = $1`,
          [submissionId, now, tier, staggerSeconds(submissionId)],
        );
      }
      return { submissionId, delta, countable, reserved, flags };
    });
  }

  // Rolling p99 of the account's positive per-interval deltas. Needs history
  // to be meaningful; below the sample floor we fall back to an absolute cap.
  private async accountP99(accountId: string, excludeSubmission: string): Promise<number | null> {
    const { rows } = await pool.query(
      `select percentile_cont(0.99) within group (order by vs.delta) as p99, count(*)::int as n
       from view_sample vs
       join submission s on s.id = vs.submission_id
       join claim cl on cl.id = s.claim_id
       where cl.account_id = $1 and vs.delta > 0 and vs.submission_id <> $2
         and vs.sampled_at > now() - interval '90 days'`,
      [accountId, excludeSubmission],
    );
    const { p99, n } = rows[0];
    return n >= config.spikeMinSamples ? Math.ceil(Number(p99)) : null;
  }

  // Cumulative countable views, derived from the sample series — never a
  // single reading (§5). Runs on the poll's transaction so it sees the sample
  // written just above.
  private async totalCountableViews(
    c: import("pg").PoolClient, submissionId: string,
  ): Promise<number> {
    const { rows: [agg] } = await c.query(
      `select coalesce(sum(delta) filter (where delta > 0 and not (anomaly_flags && '{private,music_mismatch}')), 0)::bigint as countable
       from view_sample where submission_id = $1`,
      [submissionId],
    );
    return Number(agg.countable);
  }

  // Redis-backed hourly budget marker, used by the worker loop to spread runs.
  async claimBudgetSlot(): Promise<boolean> {
    const key = `counting:run:${new Date().toISOString().slice(0, 13)}`;
    const n = await redis.incr(key);
    await redis.expire(key, 7200);
    return n <= 60;
  }
}
