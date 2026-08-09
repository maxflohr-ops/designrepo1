# Bounty Sounds — iOS

SwiftUI recreation of `BountyApp.dc.html` (the pixel-perfect design
prototype). iOS 17+, Xcode 16 project (`BountySounds.xcodeproj`), no external
dependencies.

## Fidelity notes

- **Tokens** from the handoff README: ink `#0d0d0d`, paper `#f5f3ee`, card
  `#faf9f5`, body `#2d2d2d`, muted `#6b6b6b`, olive `#6f7f5c`, treasury
  crimson `#9e3b2f`, hairline/strong borders at 15%/35% ink (`Support/Theme.swift`).
- **Fonts** bundled as static TTFs (Google Fonts): Fredericka the Great,
  Source Serif 4 (400/600/700), Space Grotesk (400–700), Space Mono (400/700),
  Permanent Marker. Registered in `Info.plist` under `UIAppFonts`.
- **Square corners everywhere** — no `cornerRadius` in the codebase. Cards are
  2px ink borders on card ground; hairline row dividers.
- **Text-only tab bar** (Space Mono uppercase, 2px underline on the active
  tab); the artist/clipper mode switch swaps the whole tab set.
- **44pt minimum hit targets** on every interactive element.
- Detail pager slides with the prototype's `320ms cubic-bezier(.22,1,.36,1)`
  curve; the board vertically snaps one contract per viewport; toasts are the
  ink "Sealed" bar, auto-dismissing at 2.6s.

## Screens

Onboarding · Board · Bounty detail (Details/Terms/Captured pager) · Claims ·
Appeal · Submit · Purse · Wire · Desk · Roster · Post a bounty (artist) ·
Review submissions (artist).

## Architecture

- `Models.swift` — display models (server-formatted amount strings).
- `API/BountyAPI.swift` — the protocol every screen talks to. Mutations map
  1:1 onto the backend's `/v1` REST surface (claim, checklist PATCH,
  submission, verdict, appeal, payout, post, top-up).
- `API/MockBountyAPI.swift` — fixture data lifted verbatim from the prototype
  so the app demos identically without a server.
- `State/AppState.swift` — the prototype's logic class, ported: screen enum,
  mode, bounty index, pager index, checklist booleans, verdicts map, purse
  selection + payout model, toast.
- `Views/` — one file per screen plus `RootView` (screen switch, tab bar,
  toast overlay).

To point at the real backend, implement `BountyAPI` over `URLSession` against
`backend/`'s REST API (attach `Idempotency-Key` on every mutating call) and
inject it in `BountySoundsApp` in place of `MockBountyAPI`.
