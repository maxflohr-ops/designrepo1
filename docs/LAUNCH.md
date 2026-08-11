# Bounty Sounds — launch checklist

Status legend: ✅ done · 🔨 built, needs verification against real services ·
⬜ open. "You" = requires the account owner; "Code" = engineering that can be
done in-session.

## Phase 0 — Foundations (done)

- ✅ Backend: modular monolith, ledger, state machines, counting job, REST API (35 tests green)
- ✅ iOS app: all 11 screens, both modes, exact design tokens, mocked API
- ✅ §8 business decisions resolved and encoded in config
- ✅ CI: backend tests + iOS simulator build on every push (`.github/workflows/ci.yml`)
- ✅ Deploy artifacts: `backend/Dockerfile`, `backend/docker-compose.yml`
- ✅ Live gateway implementations behind the interfaces (`stripeLive.ts`, `tiktokLive.ts`, `GATEWAYS=live`)
- ✅ iOS `LiveBountyAPI` (URLSession client for the /v1 surface, idempotency keys included)

## Phase 1 — Accounts & approvals (you; start immediately, longest poles)

- ⬜ **Apple Developer Program** — $99/yr. Enroll as an organization
  (needs a D-U-N-S number, free but 1–2 weeks) or as an individual (1–2 days,
  can migrate later). Blocks TestFlight and release.
- ⬜ **TikTok for Developers app** — free. Register at developers.tiktok.com,
  request **Login Kit** + **Display API** scopes (`user.info.basic`,
  `user.info.stats`, `video.list`). App review takes days–weeks. **This is the
  single biggest schedule risk**: view counting depends on it. Submit early;
  the use case ("creators authorize us to read their own video view counts")
  is squarely what the Display API is for.
- ⬜ **Stripe account + Connect** — free to open, days to activate. Enable
  Connect (Express accounts for clippers), turn on payouts, complete platform
  profile. Stripe handles KYC, money transmission, and 1099s — this is what
  makes the escrow model legal without a money-transmitter license.
- ⬜ **Bank account** for the platform's Stripe balance.

## Phase 2 — Wire the real world in (code, ~1 week once Phase 1 keys exist)

- 🔨 Stripe live gateway → verify with test-mode keys end to end
  (PaymentIntent → webhook → live bounty → transfer → refund)
- ⬜ Stripe webhook **signature verification** (replace the shared-secret
  header check in `api/server.ts` with real `Stripe-Signature` verification)
- ⬜ Stripe **PaymentSheet** in the iOS post-bounty flow (client secret is
  already returned by `POST /v1/bounties`)
- ⬜ Stripe **Express onboarding** link flow for clippers (payout method
  screen → account link URL → store `payout_method_id`)
- 🔨 TikTok live client → verify OAuth + `video.query` against the approved
  app; persist access/refresh tokens in the identity module; confirm what the
  granted scopes actually return for `music_id` (fallback: oEmbed check)
- ⬜ TikTok Login Kit in the iOS onboarding (ASWebAuthenticationSession →
  `POST /v1/auth/tiktok`)
- ⬜ App Attest for cash-out (`DCAppAttestService` assertion → backend
  verification, replacing the placeholder header)
- ⬜ Push: APNs key from the developer account → token-based APNs sender in
  `notify` (stub is in place), registration already wired (`/v1/me/push-tokens`)

## Phase 3 — Backend to production (code + you, 2–3 days)

- ⬜ Pick host (Fly.io / Render / Railway — compose file translates directly):
  API + worker + managed Postgres + managed Redis
- ⬜ `api.bountysounds.com` DNS + TLS
- ⬜ Secrets management (Stripe keys, TikTok keys, webhook secrets)
- ⬜ Backups on Postgres (the ledger is the money — PITR on)
- ⬜ Error tracking + uptime (Sentry free tier + healthcheck endpoint)
- ⬜ Rate limiting on auth + claim endpoints (Redis is already in the stack)

## Phase 4 — App hardening (code, ~1 week, overlaps Phase 2)

- ⬜ First real device build; fix whatever the simulator hid
- ⬜ Wire `LiveBountyAPI` in behind a build-config flag (Debug=mock, Release=live)
- ⬜ Session persistence (Keychain), logout, token refresh
- ⬜ Roster endpoint (`GET /v1/roster`) — app currently uses fixture data
- ⬜ Sound picker for the artist post flow (link from TikTok sound page / paste URL)
- ⬜ Empty states (no claims, empty board, zero purse) — prototype never shows them
- ⬜ Error surfaces (claim 409 slots-full, submission check failures, offline)
- ⬜ App icon (1024×1024 — great-seal on paper, square) into `AppIcon.appiconset`
- ⬜ Accessibility pass: Dynamic Type on body text, VoiceOver labels on the
  icon-free tab bar and checklist

## Phase 5 — Legal & App Review prep (you + drafts provided, ~2–3 days)

- ⬜ Terms of Service + clipper payout terms (drafts: `docs/legal/` — get a
  lawyer's pass; this app moves money)
- ⬜ Privacy policy hosted at bountysounds.com/privacy (draft provided)
- ⬜ App Store privacy "nutrition label" answers (data collected: handle,
  email, payout info via Stripe, video metadata)
- ⬜ App Review notes + demo account with seeded fixture data (metadata draft:
  `docs/appstore/metadata.md`). Key points for review: payouts are for
  real-world creative work (not digital content → external payments are
  allowed, no IAP required); TikTok login is an established third-party OAuth.

## Phase 6 — Beta → Live (1–2 weeks)

- ⬜ TestFlight internal build (Xcode Cloud or `xcodebuild archive` + Transporter)
- ⬜ 10–20 real clippers + 2–3 artists run one real bounty end to end with a
  small purse ($50–100 real money through Stripe test → then live mode)
- ⬜ Watch the counting job against real TikTok rate limits for a full 14-day
  window (or accept a shortened pilot window)
- ⬜ App Store submission (expect one rejection round on a money app — budget it)
- ⬜ Launch bounty lined up (Ridge Club purse funded before the board is public)

## Deferred (post-launch, by design)

- YouTube Shorts (per-platform window config already in place — §8 Q3)
- Android
- Staff/admin dashboard for spike-clearing and dispute resolution (SQL-only at launch)
- Taste-profile ranking beyond worked-with-artist-before
