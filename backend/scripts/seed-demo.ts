// App Review / staging demo seed: two accounts (clipper + artist), the four
// prototype bounties, and a claim in every reviewable state, so the reviewer
// sees a working marketplace on first login. Idempotent-ish: run against a
// fresh database (it refuses to run over existing bounties).
//
//   DATABASE_URL=... REDIS_URL=... npm run seed:demo
//
// Prints the two session tokens to paste into App Store Connect review notes.
import { pool, migrate } from "../src/db.js";
import { FakeStripe } from "../src/gateways/stripe.js";
import { StubTikTok } from "../src/gateways/tiktok.js";
import { BountyService } from "../src/modules/bounties/service.js";
import { CountingService } from "../src/modules/counting/service.js";
import { IdentityService } from "../src/modules/identity/service.js";

const BOUNTIES = [
  { title: "Clip the Thursday stream", song: "Northsider — Ridge Club", brief: "Best 20 seconds of the Thursday broadcast. Sound must be the listed audio, no re-uploads, caption free.", model: "per_view" as const, rate: 500, unit: 5000, purse: 50_000, cap: 12 },
  { title: "Hook challenge — new single", song: "Biting Bullets — Ridge Club", brief: "Cut to the hook at 0:42. Any format, any face. First fifteen approved clips take the purse.", model: "per_clip" as const, rate: 2000, unit: 1, purse: 40_000, cap: 15 },
  { title: "Podcast cold opens", song: "The Long Way Round ep. 118", brief: "Thirty seconds that make someone press play on the full episode. Vertical only.", model: "per_clip" as const, rate: 1200, unit: 1, purse: 26_000, cap: 20 },
  { title: "Keynote pull-quotes", song: "Founders' Day keynote", brief: "Pull the three sharpest lines from the ninety-minute keynote. Captions welcome, no music bed.", model: "per_view" as const, rate: 800, unit: 10_000, purse: 120_000, cap: 20 },
];

export async function seedDemo() {
  await migrate();
  const { rows: [{ n }] } = await pool.query("select count(*)::int as n from bounty");
  if (n > 0) throw new Error(`refusing to seed: ${n} bounties already exist`);

  const stripe = new FakeStripe();
  const tiktok = new StubTikTok();
  const bounties = new BountyService(stripe, tiktok);
  const counting = new CountingService(tiktok, bounties);
  const identity = new IdentityService(tiktok);

  const artist = await identity.loginWithTikTok("oid_demo_artist", "artist");
  const clipper = await identity.loginWithTikTok("oid_demo_clipper", "clipper");
  tiktok.seedProfile({ openId: "oid_demo_artist", handle: "ridgeclub", followerCount: 12_000, accountAgeDays: 900 });
  tiktok.seedProfile({ openId: "oid_demo_clipper", handle: "merrowcuts", followerCount: 5_400, accountAgeDays: 700 });

  const made: string[] = [];
  for (const [i, b] of BOUNTIES.entries()) {
    const { rows: [sound] } = await pool.query(
      "insert into sound (tiktok_music_id, title, artist_account_id) values ($1, $2, $3) returning *",
      [`m_demo_${i}`, b.song, artist.account.id]);
    const draft = await bounties.createDraft(artist.account.id, {
      soundId: sound.id, title: b.title, brief: b.brief, payoutModel: b.model,
      rateCents: b.rate, rateUnit: b.unit, purseCents: b.purse, slotCap: b.cap,
      deadlineAt: new Date(Date.now() + (10 + i * 4) * 86_400_000),
    });
    await bounties.markFunded(draft.clientSecret.replace(/_secret_test$/, ""), b.purse);
    made.push(draft.bounty.id);
  }

  // one live claim with a counting submission on the first bounty
  const claim = await bounties.claim(clipper.account.id, made[0]!);
  tiktok.seedVideo({
    videoId: "demo_v1", authorOpenId: "oid_demo_clipper", musicId: "m_demo_0",
    isPublic: true, viewCount: 88_000, postedAt: new Date(),
  });
  const { submission } = await bounties.createSubmission(clipper.account.id, claim.id, "demo_v1");
  await counting.pollSubmission(submission.id);

  // a settled, paid claim on the second bounty (per-clip: reserve then approve)
  const claim2 = await bounties.claim(clipper.account.id, made[1]!);
  tiktok.seedVideo({
    videoId: "demo_v2", authorOpenId: "oid_demo_clipper", musicId: "m_demo_1",
    isPublic: true, viewCount: 412_000, postedAt: new Date(),
  });
  const { submission: sub2 } = await bounties.createSubmission(clipper.account.id, claim2.id, "demo_v2");
  await bounties.verdict(artist.account.id, sub2.id, "approve");

  // a disputed claim awaiting appeal on the third
  const claim3 = await bounties.claim(clipper.account.id, made[2]!);
  tiktok.seedVideo({
    videoId: "demo_v3", authorOpenId: "oid_demo_clipper", musicId: "m_demo_2",
    isPublic: true, viewCount: 12_000, postedAt: new Date(),
  });
  const { submission: sub3 } = await bounties.createSubmission(clipper.account.id, claim3.id, "demo_v3");
  await bounties.verdict(artist.account.id, sub3.id, "dispute", "sound_mismatch");

  return {
    clipperToken: clipper.token,
    artistToken: artist.token,
    bountyIds: made,
  };
}

// bin entrypoint
if (process.argv[1]?.endsWith("seed-demo.ts") || process.argv[1]?.endsWith("seed-demo.js")) {
  seedDemo()
    .then((out) => {
      console.log("demo seeded.");
      console.log("clipper session token:", out.clipperToken);
      console.log("artist session token :", out.artistToken);
      return pool.end();
    })
    .catch((err) => {
      console.error(err.message ?? err);
      process.exitCode = 1;
      return pool.end();
    });
}
