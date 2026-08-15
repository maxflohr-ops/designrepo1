// Central config. The four §8 open questions were decided 2026-08-09:
//   Q1 fee bearer          → artist (fee grossed up out of the purse at payout;
//                            clippers receive the full advertised rate)
//   Q2 dispute holds       → a held reserve keeps counting against the purse;
//                            accrual for everyone stops at the funded total
//                            ("reserve blocks purse", zero platform fronting)
//   Q3 Shorts window       → Shorts deferred to v2; counting window is
//                            per-platform config so Shorts can differ later
//   Q4 chargebacks         → paid clippers keep their money; the spent portion
//                            becomes artist debt, the bounty freezes, the
//                            artist is suspended from posting until repaid
export const config = {
  databaseUrl:
    process.env.DATABASE_URL ??
    "postgres://pguser@localhost:5433/bounty_dev?host=/tmp",
  redisUrl: process.env.REDIS_URL ?? "redis://127.0.0.1:6390",
  port: Number(process.env.PORT ?? 3000),

  feeBearer: "artist" as const, // §8 Q1
  platformFeeBps: 1000, // 10% of the clipper amount, taken from the purse at payout

  disputeHoldPolicy: "reserve_blocks" as const, // §8 Q2
  chargebackPolicy: "artist_debt" as const, // §8 Q4

  // §8 Q3 — counting window per platform, in days. Shorts intentionally absent in v1.
  countingWindowDays: { tiktok: 14 } as Record<string, number>,

  claimWindowDays: 6,
  appealSlaHours: 72,

  // TikTok app identity. The client key is a public identifier (like an OAuth
  // client id) and ships in the app too; the secret is env-only, never here.
  tiktokClientKey: "awsr7oh3ikz2g2ay",
  // Scopes requested at login. video.publish unlocks direct posting; TikTok
  // restricts posts to SELF_ONLY until the app passes their audit, so the
  // paste-a-link submission path remains the default until then.
  tiktokScopes: "user.info.basic,user.info.stats,video.list,video.publish",
  // Flip on once TikTok's content-posting audit passes and public posts are
  // allowed — until then the app hides the direct-post path.
  directPostEnabled: process.env.TIKTOK_DIRECT_POST === "1",

  // counting job
  pollBudgetPerRun: Number(process.env.POLL_BUDGET_PER_RUN ?? 500),
  spikeMinSamples: 10,
  spikeAbsoluteFloor: 250_000, // views per interval; used until p99 has enough history

  // abuse (§7)
  firstPayoutHoldDays: 7,
  maxPurseShareBps: 4000, // one account may earn at most 40% of a purse
  claimMinAccountAgeDays: 30,
  claimMinFollowers: 100,
  artistAutoResolveDisputeRate: 0.5, // above this (min 5 verdicts), appeals auto-resolve for the clipper
  artistAutoResolveMinVerdicts: 5,
};
