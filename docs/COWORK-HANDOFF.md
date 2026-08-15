# Bounty Sounds — launch handoff (self-contained brief for a fresh agent session)

You are picking up a two-part codebase and driving it to App Store launch.
This document is the complete context; you do not need the prior session.

## What this product is

Bounty Sounds (companion app to bountysounds.com, repo
`maxflohr-ops/tiktok-bounty-beat` — reference only, do not modify): a
two-sided marketplace. Artists fund an escrow purse on a TikTok sound;
clippers claim a bounty, post a clip, and are paid from that purse against
views verified via the TikTok Display API.

## Repo state (branch `claude/bounty-sounds-ios-backend-l1cczl` in `maxflohr-ops/designrepo1`)

- `backend/` — **functionally complete** TypeScript modular monolith
  (Fastify + Postgres 16 + Redis). Five modules: identity, bounties,
  counting, treasury, notify. Append-only double-entry ledger (deferred
  zero-sum trigger); the invariant *reserves + payouts ≤ funded purse* is
  enforced in `BountyService.reserveCapped` inside the accrual transaction.
  Counting job polls on a decaying cadence with anomaly rules. Full REST API
  with mandatory `Idempotency-Key` on mutations. **54 integration tests, all
  green** (`npm test` with `DATABASE_URL`/`REDIS_URL` set; CI does this).
  Stripe and TikTok sit behind interfaces in `src/gateways/` — fakes by
  default, production impls in `stripeLive.ts` / `tiktokLive.ts`, selected by
  `GATEWAYS=live`. Also done: Stripe signature verification, Express payout
  accounts, TikTok token store + refresh, roster, App Attest registry, rate
  limits, `/healthz`, APNs sender, ops webhook, demo seed, direct post.
- `ios/` — **feature-complete but NEVER COMPILED** SwiftUI app (iOS 17+,
  Xcode 16 project; one dependency, stripe-ios via SPM). All 11 screens in
  clipper + artist modes. `MockBountyAPI` drives an offline demo by default;
  setting `BSAPIBaseURL` in Info.plist swaps in `LiveBountyAPI` (TikTok
  login, Keychain session, PaymentSheet, Express onboarding, Face ID +
  App Attest cash-out, direct post, empty/error states, app icon).
  **Everything Swift was authored in a Linux container with no compiler —
  getting it to build is job #1.**
- `docs/LAUNCH.md` — phased checklist (this brief supersedes it where they
  differ). `docs/appstore/metadata.md`, `docs/legal/privacy-policy.md` — drafts.
- CI: `.github/workflows/ci.yml`. Deploy: `backend/Dockerfile`,
  `backend/docker-compose.yml`.

## Locked business decisions (do not reopen; encoded in `backend/src/config.ts`)

1. Platform fee (10%) is borne by the **artist**: grossed out of the purse at
   reserve time; clippers get the full advertised rate.
2. A disputed submission's reserve **keeps blocking the purse** — the
   platform never fronts money.
3. **Shorts/YouTube is v2.** `platform: "shorts"` must keep returning 422.
4. Chargebacks: paid clippers keep their money; spent portion becomes artist
   debt; bounty freezes; artist suspended from posting.

## Ground rules

- Work on branch `claude/bounty-sounds-ios-backend-l1cczl` in both repos; push there only.
- `backend`: every change lands with tests; the suite must stay green. Never
  weaken the ledger (append-only, balanced transactions, derived balances) or
  the accrual invariant. All new mutating endpoints take `Idempotency-Key`.
- `ios`: preserve design fidelity — square corners only (no `cornerRadius`),
  the token palette in `Support/Theme.swift`, text-only Space Mono tab bar,
  ≥44pt hit targets, bundled fonts. Default build must keep working offline
  on `MockBountyAPI`; live backend is opt-in per build config.
- Secrets come only from the owner (Max, maxflohr@allmylifeproductions.com)
  or CI/host secret stores — never committed.

## Inputs the owner must supply (ask for whichever is missing when you need it)

| Input | Used for | Status |
|---|---|---|
| Apple Developer team id; bundle id confirmation (`com.bountysounds.ios`) | signing, TestFlight | **enrolled** — ids pending |
| App Store Connect API key (for CI upload), APNs auth key (.p8) | TestFlight automation, push | pending |
| TikTok developer app: **registered**, client key `awsr7oh3ikz2g2ay` wired in. Still needed: client **secret** (env `TIKTOK_CLIENT_SECRET`), approved Display API scopes, redirect URI, and — only for in-app posting — the Content Posting audit | login + view counting + direct post | key ✅ / scopes + secret pending (scope approval is still the critical path) |
| Stripe: secret key (test first), webhook signing secret, Connect enabled | escrow + payouts | pending |
| Hosting choice (default: Fly.io) + `api.bountysounds.com` DNS | production API | pending |

## Execution order

Work top to bottom; A and B need no owner inputs at all.

### A. Prove the build (first thing you do)
1. Push any trivial commit or re-run CI; confirm the `backend` job is green.
2. Get the `ios-build` job green on the macOS runner. Expect first-compile
   fixes in the SwiftUI sources (they've never seen a compiler) and possibly
   in `ios/BountySounds.xcodeproj/project.pbxproj` (hand-authored, Xcode 16
   `objectVersion 77` with a file-system-synchronized group). Keep fixes
   minimal; don't regenerate the project unless it's genuinely broken.
3. Done when: both CI jobs green on the branch.

### B. DONE — do not rebuild
Stripe webhook signature verification, the TikTok token store with refresh,
`GET /v1/roster`, the App Attest key registry + payout gating, Redis rate
limits on auth and claims, and `GET /healthz` are all implemented with tests.

### C–E. DONE — do not rebuild (iOS auth, payments, push)
TikTok Login Kit + Keychain sessions, the mock/live switch, Stripe
PaymentSheet + Express payout onboarding, Face ID + App Attest cash-out,
the APNs sender, the ops webhook, the demo seed, the app icon, empty states,
error surfaces, and the TikTok direct-post path are all implemented and
committed. Read the code before touching any of it. What remains on these is
*verification against real services*, which needs the owner's keys.

### F. Deploy (needs hosting + DNS decisions)
1. Fly.io (or owner's choice): two processes from `backend/Dockerfile`
   (api, worker), managed Postgres with PITR backups, Redis. Set secrets;
   `GATEWAYS=live` only in production.
2. `api.bountysounds.com` → host; TLS; point Stripe + TikTok webhooks/redirects at it.
3. Sentry (free tier) in API + worker; uptime check on `/healthz`.
4. Done when: smoke test against production in Stripe test mode passes.

### G. App hardening + store prep
1. Empty states (board empty, no claims, zero purse), error surfaces
   (slots-full 409, failed checks, offline banner) — match the design
   language: mono labels, hairlines, no new colors.
2. App icon: 1024×1024, great-seal mark on paper `#f5f3ee` (source art in
   the design bundle / `Assets.xcassets` note), into `AppIcon.appiconset`.
3. Accessibility: Dynamic Type on body text, VoiceOver labels for tab bar,
   checklist toggles, verdict buttons.
4. Seed script (`backend/scripts/seed-demo.ts`) creating the App Review demo
   account with bounties in every state.
5. TestFlight: archive + upload (Xcode Cloud or GitHub Actions with the ASC
   API key); internal testers first.
6. App Store Connect: fill from `docs/appstore/metadata.md` (privacy label
   answers included); screenshots from the simulator (6.9" + 6.5"); owner
   publishes the privacy policy at bountysounds.com/privacy from
   `docs/legal/privacy-policy.md` **after counsel review**.
7. Submit for review with the review notes in the metadata doc. Expect one
   rejection round on a money app; answer with the escrow/Stripe Connect
   explanation in those notes.

### H. Pilot before public launch
1. One real bounty, small purse, Stripe live mode, 10–20 clippers.
2. Watch the counting job against real TikTok rate limits; tune
   `pollBudgetPerRun` and cadence stagger if 429s appear.
3. Confirm ledger reconciliation: for the pilot bounty,
   `funded = paid + fees + held + refunded` exactly (SQL over `ledger_entry`).

## Owner-only actions (surface these to Max, don't wait silently)

- TikTok: app is registered (key `awsr7oh3ikz2g2ay` already wired). Still
  needed — **Display API scope approval** (the critical path for counting),
  the client **secret** into the host's secret store, and the redirect URI.
  The Content Posting audit is optional and only unlocks in-app posting.
- Activate Stripe + Connect; create webhook endpoint + share test keys.
- App Store Connect: create the app record for `com.bountysounds.ios`, ASC
  API key, APNs key.
- Legal review of ToS/privacy drafts; publish privacy policy on the website.
- Choose host + point DNS; fund the pilot purse.

## Definition of launched

App live on the App Store; production backend serving `GATEWAYS=live`; one
real bounty funded, counted, approved, and cashed out end to end; ledger
reconciles to the cent.
