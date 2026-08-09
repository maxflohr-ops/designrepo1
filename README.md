# Bounty Sounds — iOS app + backend

Built from `design_handoff_bounty_sounds` (README, `BountyApp.dc.html`,
`Bounty Sounds Backend Spec.dc.html`). Companion to bountysounds.com
(`maxflohr-ops/tiktok-bounty-beat`): artists fund escrow purses on TikTok
sounds; clippers claim bounties, post clips, and get paid on verified views.

| directory  | contents |
|------------|----------|
| `backend/` | TypeScript modular monolith — Postgres + Redis, five modules, append-only double-entry ledger, Stripe Connect escrow, decaying-cadence view counting, §6 REST API with idempotency keys. 35 integration tests. |
| `ios/`     | SwiftUI app, Xcode 16 project — all 11 screens in clipper + artist modes, exact design tokens and bundled fonts, mock API behind a protocol with prototype fixture data. |

The four §8 open questions were decided 2026-08-09: artist bears the platform
fee · a disputed reserve keeps blocking the purse · Shorts deferred to v2
(per-platform window config) · chargebacks become artist debt with clippers
kept whole. Details in `backend/README.md`.
