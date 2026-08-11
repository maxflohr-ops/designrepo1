# App Store metadata (draft)

**Name:** Bounty Sounds
**Subtitle:** Clip it. Claim it. Cash it.
**Bundle ID:** com.bountysounds.ios
**Category:** Entertainment (secondary: Music)
**Age rating:** 17+ (unrestricted web access: no; user-generated content: linked, not hosted)

## Description

The bounty board for sound. Artists post a funded purse on a TikTok sound.
Clippers claim a contract, cut a clip, post it, and get paid on verified
views. The purse is posted before you cut — escrowed up front, paid out on
counts read from TikTok's public counter.

- Swipe the board: every contract shows the purse, the rate, the deadline,
  and the open slots before you commit.
- Seize a contract and work the checklist: save the sound, cut the clip,
  post it, lodge the link.
- Automatic checks verify the sound, the window, your handle, and duplicates
  the moment you submit.
- Watch views accrue for 14 days. Cleared money is cashable with Face ID.
- Artist mode is the other side of the desk: fund a purse, review
  submissions, approve to pay instantly.

No invites. No gated Discord. The purse can't run dry mid-window — it's
funded before the board ever shows it.

## Keywords

clips, clipping, tiktok sounds, bounty, creator economy, ugc, get paid,
music promotion, viral clips, artists

## Review notes (for App Review)

- Demo account: seeded with fixture bounties, claims in every state, and a
  purse balance — credentials supplied in App Store Connect.
- Money flow: artists fund escrow via Stripe; clippers are paid via Stripe
  Connect for real-world creative work (video editing/posting). Payouts are
  compensation for services, not purchases of digital content, so no IAP is
  involved (Guideline 3.1.5(a) — people, not content).
- TikTok login uses TikTok's official Login Kit OAuth. We read only the
  authenticated user's own profile and video view counts via the Display
  API, with their consent, to verify payouts.
- Face ID (LocalAuthentication) gates cash-out only; the usage string
  explains this.
- User-generated video stays on TikTok; the app links out and never hosts
  third-party content.

## Privacy nutrition label (answers)

| Data | Collected | Linked to user | Tracking |
|------|-----------|----------------|----------|
| TikTok handle + open id | yes | yes | no |
| Video metadata (ids, view counts) | yes | yes | no |
| Payout details | via Stripe (not stored by us) | yes | no |
| Push token | yes | yes | no |
| Analytics/ads identifiers | no | — | no |
