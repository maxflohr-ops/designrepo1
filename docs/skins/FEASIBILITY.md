# Skins over a scrolling feed — what's buildable, what isn't

**Question asked:** put a TikTok scroll on the bottom half of the screen, run
swappable mini-apps ("skins" — cookbook, etc.) on the top half, charge $1 per
skin, and sell the resulting behavioural data.

**Short answer:** the product shape is good and two thirds of it is buildable
today. The two parts that don't survive contact with TikTok's and Apple's terms
are (a) sourcing the bottom feed from TikTok's public/For-You content, and
(b) selling user-level behavioural data. Both have replacements that are
*better* businesses for us, described below.

---

## 1. The split screen and the skins — yes, build it

Nothing in either rulebook stops us from rendering our own UI above a video
pane. This is ordinary app layout. Implemented in `ios/BountySounds/Views/StageView.swift`
plus `ios/BountySounds/Skins/`.

Two constraints shaped the implementation:

- **Skins are native SwiftUI, not HTML5.** Apple guideline 4.7 permits HTML5/JS
  mini apps, but 4.7.2 forbids bridging native platform APIs into them without
  prior Apple approval, and the Mini Apps Partner Program adds a review layer we
  don't need. Native skins compiled into the binary sidestep 4.7 entirely.
- **The skin catalog is data, the skins are code.** New skins need an App Store
  submission. Copy, pricing, ordering, and availability come from the catalog and
  can change server-side. Budget for that asymmetry when planning releases.

## 2. The $1 unlock — yes, with the standard tax

Non-consumable StoreKit 2 in-app purchases. Apple takes 30% (15% under the Small
Business Program, which we qualify for). A $1 skin nets $0.85. That is fine for a
catalog play but it means **skins are a retention and data instrument, not a
revenue line** — at $0.85 a unit you need volume we won't have on day one. See §5.

Implemented in `ios/BountySounds/Support/Entitlements.swift`. Product IDs follow
`com.bountysounds.skin.<id>`. Purchases restore across devices via
`Transaction.currentEntitlements`; there is no server receipt check yet (noted in
§6 as remaining work).

## 3. The bottom feed — **not** TikTok's public content

This is the blocker, and it's worth being exact about why, because the fix is
easy once you accept it.

**There is no public feed API.** TikTok's Display API returns data *only for the
user who authenticated with your app* — their own videos, their own profile. It
does not expose other users' content, and there is no endpoint of any kind for
the For-You page or any algorithmic feed. This is already documented in our own
`backend/src/gateways/tiktokLive.ts` header comment, because the view-counting
job runs into the same wall. The Research API does allow keyword and hashtag
queries across public content, but access is limited to approved academic
researchers — we would not qualify.

**Scraping is out.** Beyond the obvious risk, TikTok's Developer Terms §III.3(h)
prohibits collecting personal data from TikTok users to "build databases or
similar records," which is precisely what a scraped feed cache is.

**A general feed also collides with §III.3(p)**, which forbids using TikTok
Developer Services or TikTok Information "to compete with or replicate any TikTok
Services." A vertically-paged, infinite, algorithmic feed of TikTok videos is a
replica of the core TikTok service. Even built from technically-permitted embeds,
that is the clause that gets the developer account pulled.

### What we can legitimately show

The **official embed player**, one post per iframe, unmodified. It supports
`autoplay`, `muted`, `loop`, chrome-hiding query parameters, and bidirectional
control via `window.postMessage` (`play`, `pause`, `mute`, `unMute`,
`onPlayerReady`, `onStateChange`). That is enough to drive a paged feed.

The question is what goes *in* it — and we already have an answer that a
general-purpose app doesn't:

> **The bounty board is our feed.**

Clips submitted against a bounty are posted by clippers who connected their
TikTok account at onboarding, whose own videos we are authorised to read, and who
submitted the clip to us on purpose. Each one has a `share_url`. A vertical pager
of *bounty submissions for a given sound* is:

- sourced from content we have a first-party relationship with,
- scoped to a contract rather than the whole platform, so it is a review and
  discovery surface for our own marketplace, not a TikTok replica,
- **inventory the artist is already paying for.** Artists fund purses to get a
  sound in front of people. A feed of that sound's clips is the artist's money
  doing its job.

That last point is the one to hold onto. The version of this idea that is legal
is also the version that is on-strategy.

`ClipFeedView` renders exactly this: bounty-scoped, embed-player-backed, with a
fixture fallback so the prototype runs offline like the rest of the app.

## 4. Selling the behavioural data — reframe it

Three separate problems with "collect what they do and sell it":

1. **TikTok's terms.** §II.1 licenses TikTok Information on a "personal,
   non-exclusive, non-sublicensable, non-transferrable basis," and §III.3(b)
   forbids sublicensing without written authorisation. Anything derived from
   TikTok data cannot be packaged and sold onward. §VI additionally requires
   deleting all TikTok Information on termination — hard to honour if you've sold
   derivatives of it.
2. **Apple guideline 5.1.2.** Personal data may not be shared with third parties
   without clearly disclosing the recipient and purpose *and* obtaining explicit
   consent first. Apple tightened this in November 2025 for third-party AI
   specifically, and reviewers now look for the consent gate. A data-resale
   business model disclosed honestly in an App Store privacy label is a slow
   review at best.
3. **GDPR/CCPA.** "Sale of personal information" triggers opt-out rights, a Do
   Not Sell link, and contract obligations we have no legal function to service.

### The version that works

We don't need user-level data. **We need aggregate attention analytics, and our
customers are already on the platform.**

Artists and labels fund purses. What they cannot buy anywhere else is: *did the
sound hold attention, and under what conditions?* Our split screen is a
measurement instrument nobody else has — it produces dwell time on a specific
sound while a known secondary task is running.

Sellable as a first-party report, entirely from our own app surface:

> "Clips on your sound held a median 14.2s with the cookbook skin active vs 8.1s
> with no skin. Completion rate 61% vs 38%. n = 4,930 sessions."

That is a genuinely novel dataset, it is **ours** (generated on our surface, not
derived from TikTok Information), it sells to customers who already have a
billing relationship with us, and it requires no consent theatre because it is
aggregated and never leaves as personal data. Suppression floor of n ≥ 50
sessions per cell before any figure is reportable.

`ios/BountySounds/Support/Attention.swift` records exactly the fields this needs
and nothing more — no content, no free text, no identifiers beyond a rotating
per-session id.

### Event schema

| event | fields |
|---|---|
| `stage_open` | `session_id`, `bounty_id`, `skin_id`, `split_ratio` |
| `clip_impression` | `session_id`, `clip_id`, `bounty_id`, `skin_id`, `dwell_ms`, `completed`, `split_ratio` |
| `skin_switch` | `session_id`, `from_skin_id`, `to_skin_id`, `at_ms` |
| `skin_interaction` | `session_id`, `skin_id`, `action` (enum, not free text), `at_ms` |
| `split_change` | `session_id`, `ratio`, `at_ms` |
| `stage_close` | `session_id`, `duration_ms`, `clips_seen` |

`session_id` is a fresh UUID per stage session. It is deliberately *not* joined
to `open_id` or the user record — the reports don't need it, and not collecting
it is what keeps this out of 5.1.2's scope.

### Ingest contract (backend work, not yet built)

```
POST /v1/attention/batch
Idempotency-Key: <uuid>
{ "events": [ { "type": "clip_impression", "at": "2026-08-23T09:33:00Z", ... } ] }
→ 202 { "accepted": <int> }
```

Batched on stage close and on background, capped at 200 events per request,
dropped silently on failure — telemetry must never block or fail the UI.

## 5. What this is actually worth

Being straight about the money, because the $1 figure invites a wrong model:

- **Skins at $0.85 net** are not the business. Treat them as the thing that makes
  the stage sticky and the attention data denser.
- **The attention report is the business.** It attaches to an artist relationship
  that already carries a purse and a platform fee. Pricing it as a tier on the
  artist side (report included above $X purse, or a flat monthly) will out-earn
  the skin catalog by an order of magnitude and costs nothing per unit.
- **The skins pay for themselves in a second way:** a paid skin is a strong
  intent signal, and skin choice is the covariate that makes the attention report
  interesting. Without skins the report is just dwell time.

## 6. Remaining work

Not built in this pass, listed so nobody assumes otherwise:

- **Backend `attention` module** — the ingest endpoint above, the aggregation
  job, and the n ≥ 50 suppression floor. Nothing exists server-side yet.
- **Server-side receipt validation** for skin purchases. Client-side
  `Transaction.currentEntitlements` is trusted today; a jailbroken device unlocks
  skins for free. Acceptable while skins are a retention instrument, not
  acceptable if they ever carry real revenue.
- **The artist-facing report UI.** Section 4's whole thesis, with no screen yet.
- **Legal review of the bounty-scoped feed** before it ships. §3's reading is
  defensible and materially safer than a general feed, but "defensible" is my
  read of the clauses, not counsel's.

## Sources

- [TikTok Developer Terms of Service](https://www.tiktok.com/legal/page/global/tik-tok-developer-terms-of-service/en) — §II.1, §III.3(b), §III.3(h), §III.3(p), §VI
- [TikTok Display API overview](https://developers.tiktok.com/doc/display-api-overview)
- [TikTok Embed Player](https://developers.tiktok.com/doc/embed-player)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — 4.7, 4.7.2, 5.1.2
- [Apple, updated App Review Guidelines (Nov 2025)](https://developer.apple.com/news/?id=ey6d8onl)
