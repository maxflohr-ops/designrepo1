import { pool, migrate, withTxn } from "../src/db.js";
import { FakeStripe } from "../src/gateways/stripe.js";
import { StubTikTok } from "../src/gateways/tiktok.js";
import { BountyService } from "../src/modules/bounties/service.js";
import { CountingService } from "../src/modules/counting/service.js";
import { TreasuryService } from "../src/modules/treasury/service.js";
import { IdentityService } from "../src/modules/identity/service.js";

export function services() {
  const stripe = new FakeStripe();
  const tiktok = new StubTikTok();
  const bounties = new BountyService(stripe, tiktok);
  const counting = new CountingService(tiktok, bounties);
  const treasury = new TreasuryService(stripe);
  const identity = new IdentityService(tiktok);
  return { stripe, tiktok, bounties, counting, treasury, identity };
}

export async function resetDb() {
  await migrate();
  await pool.query(`
    truncate wire_item, idempotency_key, ledger_entry, dispute, view_sample,
             submission, claim, bounty, sound, device_push_token, session, account
    restart identity cascade`);
}

export async function mkAccount(handle: string, roles = ["clipper"], openId = `oid_${handle}`) {
  const { rows: [a] } = await pool.query(
    "insert into account (tiktok_open_id, handle, roles) values ($1,$2,$3) returning *",
    [openId, handle, roles],
  );
  return a;
}

export async function mkSound(musicId: string, title: string, artistId?: string) {
  const { rows: [s] } = await pool.query(
    "insert into sound (tiktok_music_id, title, artist_account_id) values ($1,$2,$3) returning *",
    [musicId, title, artistId ?? null],
  );
  return s;
}

export function goodProfile(tiktok: StubTikTok, openId: string, handle: string) {
  tiktok.seedProfile({ openId, handle, followerCount: 5000, accountAgeDays: 400 });
}

// Full happy path up to a counting submission: artist + funded bounty +
// clipper claim + passing submission.
export async function fundedBountyWithSubmission(opts: {
  purseCents?: number; rateCents?: number; rateUnit?: number;
  payoutModel?: "per_view" | "per_clip"; views?: number;
} = {}) {
  const svc = services();
  const artist = await mkAccount("ridgeclub", ["artist"]);
  const clipper = await mkAccount("merrowcuts");
  goodProfile(svc.tiktok, clipper.tiktok_open_id, "merrowcuts");
  const sound = await mkSound("m_ridge", "Northsider — Ridge Club", artist.id);

  const { bounty, clientSecret } = await svc.bounties.createDraft(artist.id, {
    soundId: sound.id, title: "Clip the Thursday stream", brief: "Best 20 seconds.",
    payoutModel: opts.payoutModel ?? "per_view",
    rateCents: opts.rateCents ?? 500, rateUnit: opts.rateUnit ?? 5000,
    purseCents: opts.purseCents ?? 50_000, slotCap: 12,
    deadlineAt: new Date(Date.now() + 12 * 86400_000),
  });
  const intentId = clientSecret.replace(/_secret_test$/, "");
  await svc.bounties.markFunded(intentId, opts.purseCents ?? 50_000);

  const claim = await svc.bounties.claim(clipper.id, bounty.id);
  svc.tiktok.seedVideo({
    videoId: "v1", authorOpenId: clipper.tiktok_open_id, musicId: "m_ridge",
    isPublic: true, viewCount: opts.views ?? 0, postedAt: new Date(),
  });
  const { submission } = await svc.bounties.createSubmission(clipper.id, claim.id, "v1");
  return { svc, artist, clipper, sound, bounty, claim, submission, intentId };
}

export { pool, withTxn };
