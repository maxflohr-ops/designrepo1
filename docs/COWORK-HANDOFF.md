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
  with mandatory `Idempotency-Key` on mutations. **35 integration tests, all
  green** (`npm test` with `DATABASE_URL`/`REDIS_URL` set; CI does this).
  Stripe and TikTok sit behind interfaces in `src/gateways/` — fakes by
  default, production impls in `stripeLive.ts` / `tiktokLive.ts`, selected by
  `GATEWAYS=live`.
- `ios/` — **visually complete** SwiftUI app (iOS 17+, Xcode 16 project,
  no dependencies). All 11 screens in clipper + artist modes on fixture data
  via `MockBountyAPI`; `LiveBountyAPI` (URLSession, idempotency keys) exists
  but is not yet wired in. **The app has never been compiled** — this repo
  was authored in a Linux container; the `ios-build` CI job on a macOS runner
  is the build gate.
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
| TikTok developer app: client key/secret, approved scopes (`user.info.basic`, `user.info.stats`, `video.list`), redirect URI | login + view counting | **not registered yet — owner action, chase this first, it's the critical path** |
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

### B. Backend production wiring (no external accounts needed)
1. **Stripe webhook signatures**: replace the `x-webhook-secret` header check
   in `src/api/server.ts` with real `Stripe-Signature` verification
   (HMAC-SHA256 over `t.payload` per Stripe's scheme — implement with
   node:crypto, no SDK; keep the shared-secret path for `GATEWAYS=fake`).
   Test with synthetic signed payloads.
2. **TikTok token persistence**: `LiveTikTok` needs `tokenFor(openId)`.
   Add `tiktok_token` table (open_id PK, access_token, refresh_token,
   expires_at, scopes) + refresh logic in the identity module; wire
   `makeGateways()` to pass a pool-backed `tokenFor`. Extend
   `exchangeCode` to persist tokens. Tests with the stub.
3. **Roster endpoint**: `GET /v1/roster` — rank accounts by paid-out cents
   (`payout_clear` credits) over a rolling 90 days; include rank, handle,
   paid views (sum of countable deltas), bounty count, and an `isYou` flag.
   Then implement `fetchRoster()` in `LiveBountyAPI` against it.
4. **App Attest verification endpoint**: `POST /v1/me/attest` accepting an
   App Attest key id + assertion; store verified key ids per account; make
   `POST /v1/me/payouts` accept assertions from a registered key (keep the
   current header check as the `GATEWAYS=fake` path). Full CBOR validation
   can start minimal (structure + rp id hash) with a TODO for cert-chain
   pinning; the design goal is the interface, so the iOS side can build.
5. **Rate limiting**: Redis token bucket on `/v1/auth/tiktok` (per IP) and
   `POST /v1/bounties/:id/claims` (per account). Tests.
6. **Health endpoint** `GET /healthz` (DB + Redis ping) for the host's checks.
7. Done when: suite green with new tests covering each of the above.

### C. iOS auth + live mode (needs TikTok keys to test, build it before they arrive)
1. TikTok Login Kit: `ASWebAuthenticationSession` from the onboarding CTAs →
   authorize URL → callback code → `POST /v1/auth/tiktok` → store the session
   token in Keychain (small Keychain helper, no dependency).
2. Build-config switch: Debug → `MockBountyAPI`; a `LIVE_API` xcconfig flag +
   base URL → `LiveBountyAPI`. Logout clears Keychain and returns to onboarding.
3. Session restore on launch; 401 → onboarding.
4. Done when: app compiles in CI in both configurations; mock flow unchanged.

### D. iOS payments (needs Stripe test keys to verify)
1. Add `stripe-ios` via SPM (PaymentSheet only).
2. Post-bounty flow: `POST /v1/bounties` → client secret → PaymentSheet →
   on success show the existing "Purse funded" toast; bounty goes live via
   webhook (test-mode webhook against the deployed backend or stripe-cli).
3. Top-up button → same flow via `POST /v1/bounties/:id/topups`.
4. Payout method screen: `POST /v1/me/payout-account` (new backend endpoint
   producing a Stripe Express account-link URL) → open in
   `SFSafariViewController` → store `payout_method_id` on return.
5. Cash out: Face ID via LocalAuthentication + App Attest assertion (from B4)
   replacing the placeholder header in `LiveBountyAPI.cashOut`.
6. Done when: full money loop runs in Stripe test mode: fund → live →
   claim → submit → poll (stub counts) → approve → cash out.

### E. Push notifications (needs APNs key)
1. Backend: token-based APNs (JWT ES256 via node:crypto, HTTP/2 to
   `api.push.apple.com`) replacing the `sendPush` stub in
   `src/modules/notify/service.ts`; env `APNS_KEY_ID`, `APNS_TEAM_ID`,
   `APNS_KEY_P8`, `APNS_BUNDLE_ID`.
2. iOS: notification permission prompt after first claim (not at launch),
   registration → `POST /v1/me/push-tokens`.
3. Done when: a wire event produces a push on a TestFlight build.

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

- Register the TikTok developer app + request scopes (**do this first — it
  gates counting and is the schedule's critical path**).
- Activate Stripe + Connect; create webhook endpoint + share test keys.
- App Store Connect: create the app record for `com.bountysounds.ios`, ASC
  API key, APNs key.
- Legal review of ToS/privacy drafts; publish privacy policy on the website.
- Choose host + point DNS; fund the pilot purse.

## Definition of launched

App live on the App Store; production backend serving `GATEWAYS=live`; one
real bounty funded, counted, approved, and cashed out end to end; ledger
reconciles to the cent.
