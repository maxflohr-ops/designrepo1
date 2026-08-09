# Bounty Sounds — backend

Implementation of `Bounty Sounds Backend Spec.dc.html` (v1, August 2026): a
two-sided escrow over a view counter. TypeScript modular monolith on
Fastify + Postgres + Redis.

## Modules (§1)

One process, five module boundaries under `src/modules/`:

| module   | owns |
|----------|------|
| identity | TikTok OAuth (stub), session tokens, role grants, device push tokens |
| bounties | bounty lifecycle, slots, claims, claim expiry, submissions, disputes |
| counting | scheduled view polls, the sample series, verification and anomaly flags |
| treasury | escrow, the double-entry ledger, holds, payouts, refunds, chargebacks |
| notify   | the in-app wire + APNs stub, wired into every money event |

External services sit behind interfaces in `src/gateways/`: `StripeGateway`
(Stripe Connect, platform as escrow holder) and `TikTokClient` (Display API).
Both ship as fakes/stubs; nothing above the interface changes at ship time.

## Money (§2, §4)

Money is never a column on a business object. `ledger_entry` is append-only
(enforced by DB rules), double-entry (a deferred constraint trigger rejects
any transaction whose legs don't sum to zero), and balances are always derived
(`src/domain/ledger.ts`). Flows: `purse_fund → accrual_reserve →
payout_clear → cash_out`, with `release_reserve`, `refund`, and `chargeback`
on the exit paths.

**The invariant** — reserves + paid-out never exceed the funded total — is
enforced in `BountyService.reserveCapped`, inside the same transaction as the
reserve write, under the bounty row lock. When a purse would be
oversubscribed, accrual stops at the remaining balance and the bounty moves to
`closing` (first posted, first paid).

## §8 decisions (resolved 2026-08-09)

1. **Fee bearer: artist.** The 10% fee is grossed up out of the purse when a
   reserve is written; clippers receive the full advertised rate; the artist's
   refund is what's left. Fee is taken at payout, never at funding.
2. **Dispute holds: reserve blocks the purse.** A held reserve keeps counting
   against the funded total; the platform never fronts the difference.
3. **Shorts: deferred to v2.** The counting window is per-platform config
   (`config.countingWindowDays`); `platform: "shorts"` returns 422 today.
4. **Chargebacks: clippers keep their money.** Remaining escrow leaves with
   the reversal, the spent portion books as artist debt, the bounty freezes,
   and the artist is suspended from posting until the debt clears.

## Counting job (§5)

`CountingService.runOnce` polls each counting submission on the decaying
cadence (hourly < 48 h, six-hourly to day 7, daily to day 14; per-submission
`next_poll_at` with deterministic stagger). Rules before a delta counts: video
still public and still on the contract's `music_id`; negative deltas recorded,
never accrued; a delta above the account's rolling p99 flags `spike` and holds
the submission (reserved, unpaid) for a human; a deleted video voids the
submission and releases its reserve. Over poll budget, submissions degrade to
the next tier and the next sample carries a `degraded` flag.

## API (§6)

All §6 endpoints plus the app-facing extensions (`/v1/me/wire`,
`/v1/me/review`, `/v1/bounties/:id/topups`, auth, webhooks). Every mutating
call requires an `Idempotency-Key` (first writer wins; same key + same body
replays the stored response; same key + different body → 422). The board has
ETag + cursor pagination and a `?sound=` filter for the TikTok share-sheet
deep link. Cash out requires an `X-Device-Attestation` header (App Attest,
surfaced in-app as Face ID).

Abuse rules (§7): 7-day first-payout hold, 40% per-account purse-share cap,
account age/follower floor at claim time, auto-resolve appeals against
serial-disputing artists, and the sample series is never discarded.

## Run

```sh
npm install
# Postgres ≥ 15 and Redis running; see src/config.ts for env vars
DATABASE_URL=postgres://... REDIS_URL=redis://... npm run migrate
npm run dev      # API on :3000
npm run worker   # claim expiry + counting loop
npm test         # 35 integration tests against real Postgres/Redis
```
