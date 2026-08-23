# Bounty Sounds — launch checklist

Status legend: ✅ done · 🔨 built, needs verification against real services ·
⬜ open. "You" = requires the account owner; "Code" = engineering that can be
done in-session.

## Phase 0 — Foundations (done)

- ✅ Backend: modular monolith, ledger, state machines, counting job, REST API (54 tests green)
- ✅ iOS app: all 11 screens, both modes, exact design tokens, mocked API
- ✅ §8 business decisions resolved and encoded in config
- ✅ CI: backend tests + iOS simulator build on every push (`.github/workflows/ci.yml`)
- ✅ Deploy artifacts: `backend/Dockerfile`, `backend/docker-compose.yml`
- ✅ Live gateway implementations behind the interfaces (`stripeLive.ts`, `tiktokLive.ts`, `GATEWAYS=live`)
- ✅ iOS `LiveBountyAPI` (URLSession client for the /v1 surface, idempotency keys included)

## Phase 1 — Accounts & approvals (you; start immediately, longest poles)

- ✅ **Apple Developer Program** — enrolled. Still to pull from it: the APNs
  auth key (.p8), an App Store Connect API key for CI upload, and the app
  record for `com.bountysounds.ios`.
- 🔨 **TikTok for Developers app** — registered. Client key `awsr7oh3ikz2g2ay`
  is wired into the backend config and the app's Info.plist (it's a public
  identifier; the **client secret** is env-only — `TIKTOK_CLIENT_SECRET` —
  and must never be committed). Still needed from TikTok:
  - **Display API scopes** approved (`user.info.basic`, `user.info.stats`,
    `video.list`) — view counting depends on these; still the critical path.
  - **Content Posting audit** (`video.publish`) if we want in-app posting to
    produce public videos. Unaudited, TikTok forces posts to SELF_ONLY, which
    can't earn views — so direct post ships dark (`TIKTOK_DIRECT_POST=1`).
- ⬜ **Stripe account + Connect** — free to open, days to activate. Enable
  Connect (Express accounts for clippers), turn on payouts, complete platform
  profile. Stripe handles KYC, money transmission, and 1099s — this is what
  makes the escrow model legal without a money-transmitter license.
- ⬜ **Bank account** for the platform's Stripe balance.

## Phase 2 — Wire the real world in (code, ~1 week once Phase 1 keys exist)

- 🔨 Stripe live gateway → verify with test-mode keys end to end
  (PaymentIntent → webhook → live bounty → transfer → refund)
- ✅ Stripe webhook **signature verification** — `Stripe-Signature` HMAC over
  the raw body; shared-secret fallback only outside live mode
- ✅ Stripe **PaymentSheet** in the iOS post-bounty and top-up flows
  (stripe-ios via SPM; mock mode skips the payment step)
- ✅ Stripe **Express onboarding** for clippers (`POST /v1/me/payout-account`
  → hosted account link from the purse screen; `payout_method_id` stored)
- 🔨 TikTok live client: token persistence + auto-refresh done; client key
  wired; still to verify OAuth + `video.query` against the approved app and
  confirm `music_id` coverage on the granted scopes (fallback: oEmbed check)
- 🔨 **Direct post (Content Posting API)** built end to end — creator_info,
  video/init, upload, status poll, and submission lodged from the video id
  TikTok returns. Gated off until the audit passes. **Open product question:
  a FILE_UPLOAD post only satisfies the sound check if TikTok links the
  uploaded audio back to the contract's `music_id`; when it doesn't, the
  submission is rejected at lodge time (Terms rule 01 — a re-upload doesn't
  count). Verify this behavior against a real post before relying on it.**
- ✅ TikTok Login Kit in the iOS onboarding (ASWebAuthenticationSession →
  backend https callback → app scheme → `POST /v1/auth/tiktok`); live mode
  only — the offline design demo is untouched
- ✅ App Attest for cash-out: key registration + payout gating server-side,
  `DCAppAttestService` key generation/assertions + Face ID gate in the app
  (full CBOR attestation validation server-side remains a hardening TODO)
- 🔨 Push: token-based APNs sender implemented (ES256 JWT over HTTP/2, silent
  until APNS_* env is set); needs the APNs key from the developer account

## Phase 3 — Backend to production (code + you, 2–3 days)

- ⬜ Pick host (Fly.io / Render / Railway — compose file translates directly):
  API + worker + managed Postgres + managed Redis
- ⬜ `api.bountysounds.com` DNS + TLS
- ⬜ Secrets management (Stripe keys, TikTok keys, webhook secrets)
- ⬜ Backups on Postgres (the ledger is the money — PITR on)
- ⬜ Error tracking + uptime (Sentry free tier + healthcheck endpoint)
- ✅ Rate limiting on auth (per IP) and claims (per account) via Redis

## Phase 4 — App hardening (code, ~1 week, overlaps Phase 2)

- ⬜ First real device build; fix whatever the simulator hid
- ✅ Mock/live switch: `BSAPIBaseURL` in Info.plist (empty = offline design
  demo on `MockBountyAPI`; set = `LiveBountyAPI` against the backend)
- ✅ Session persistence (Keychain), sign-out on the Desk, session restore at
  launch (token refresh: sessions last 30 days, re-login after)
- ✅ Roster endpoint (`GET /v1/roster`, 90-day payout standings) wired into
  `LiveBountyAPI.fetchRoster`
- ✅ Sound picker: paste-a-link field in the post flow + `POST /v1/sounds/resolve`
- ✅ Empty states for board, claims desk, ledger, and wire
- ✅ Error surfaces: claim 409/403 toasts by error code, cash-out failures, offline
- ✅ App icon: 1024×1024 great-seal on paper in `AppIcon.appiconset`
- ✅ Accessibility: decorative art hidden from VoiceOver, checklist rows
  labeled with state (tab bar is text-only and reads natively)

## Phase 5 — Legal & App Review prep (you + drafts provided, ~2–3 days)

- ⬜ Terms of Service + clipper payout terms (drafts: `docs/legal/` — get a
  lawyer's pass; this app moves money)
- ⬜ Privacy policy hosted at bountysounds.com/privacy (draft provided)
- ⬜ App Store privacy "nutrition label" answers (data collected: handle,
  email, payout info via Stripe, video metadata)
- 🔨 App Review notes + demo seed (`npm run seed:demo`) ready (metadata draft:
  `docs/appstore/metadata.md`). Key points for review: payouts are for
  real-world creative work (not digital content → external payments are
  allowed, no IAP required); TikTok login is an established third-party OAuth.
  **Amend this note if the Stage ships:** skins *are* digital content and go
  through In-App Purchase, so the app would carry both — payouts outside IAP,
  skins inside it. Reviewers read the mix as a red flag unless the note draws
  the line first.

## Phase 6 — Beta → Live (1–2 weeks)

- ⬜ TestFlight internal build (Xcode Cloud or `xcodebuild archive` + Transporter)
- ⬜ 10–20 real clippers + 2–3 artists run one real bounty end to end with a
  small purse ($50–100 real money through Stripe test → then live mode)
- ⬜ Watch the counting job against real TikTok rate limits for a full 14-day
  window (or accept a shortened pilot window)
- ⬜ App Store submission (expect one rejection round on a money app — budget it)
- ⬜ Launch bounty lined up (Ridge Club purse funded before the board is public)

## Phase 7 — The Stage & skins (prototyped, not launch-blocking)

Split screen: a skin above, the bounty's clip feed below. Analysis and the
constraints that shaped it are in `docs/skins/FEASIBILITY.md` — read §3 and §4
before touching the feed source or the telemetry, they are the two places this
design can go wrong legally.

- ✅ Stage shell, draggable split, skin switcher (`ios/BountySounds/Views/StageView.swift`)
- ✅ Three skins — Tally (free), Cookbook ($1), Lyric Sheet ($1) (`ios/BountySounds/Skins/`)
- ✅ StoreKit 2 unlocks, restore, localized pricing (`Support/Entitlements.swift`)
- ✅ Bounty-scoped clip feed over TikTok's official embed player (`Views/ClipFeedView.swift`)
- ✅ Attention event schema + client recorder (`Support/Attention.swift`)
- ✅ Privacy policy updated for Stage telemetry and skin purchases
- ⬜ **Backend `attention` module** — `POST /v1/attention/batch`, aggregation
  job, n ≥ 50 suppression floor. Nothing server-side exists; the client drops
  its batches in mock builds and posts into the void in configured ones.
- ⬜ **Artist-facing attention report** — the actual business case in §5, with
  no screen yet
- ⬜ **Server-side receipt validation** for skin purchases (client-trusted today)
- ⬜ **App Store Connect products** — `com.bountysounds.skin.cookbook`,
  `com.bountysounds.skin.lyrics`, non-consumable, Tier 1
- ⬜ **Embed player `onStateChange`** via postMessage, to replace the dwell-time
  proxy currently standing in for clip completion
- ⬜ **Counsel review of the feed scope** before it ships

## Deferred (post-launch, by design)

- YouTube Shorts (per-platform window config already in place — §8 Q3)
- Android
- Staff/admin dashboard for spike-clearing and dispute resolution (SQL-only at launch)
- Taste-profile ranking beyond worked-with-artist-before
