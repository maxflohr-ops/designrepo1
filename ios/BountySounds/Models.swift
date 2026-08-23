import Foundation

// Display models. Amount strings arrive server-formatted; the app never does
// money math beyond the purse-preset preview on the post screen.

struct Bounty: Identifiable, Equatable {
    let id: String
    let serial: String
    let purse: String
    let title: String
    let song: String
    let brief: String
    let rate: String
    let platform: String
    let deadline: String
    let slots: String
}

struct CapturedClip: Identifiable, Equatable {
    let id: String
    let serial: String
    let handle: String
    let views: String
    let paid: String
}

struct ChecklistStep: Identifiable, Equatable {
    var id: Int
    let title: String
    let subtitle: String
}

struct ReviewingClaim: Identifiable, Equatable {
    let id: String
    let title: String
    let meta: String
    let state: String   // "disputed" | "approved"
}

struct EvidenceRow: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let value: String
}

struct SubmissionCheck: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let state: String
    let passed: Bool?   // nil renders muted (informational)
}

struct LedgerRow: Identifiable, Equatable {
    let id: String
    let title: String
    let meta: String
    let amount: String
    let tone: Tone
    enum Tone { case credit, debit, held }
}

struct WireItem: Identifiable, Equatable {
    let id: String
    let body: String
    let when: String
    let unread: Bool
    let tone: Tone
    enum Tone { case money, warn, info }
}

struct RosterRow: Identifiable, Equatable {
    let id: String
    let rank: String
    let initials: String
    let handle: String
    let meta: String
    let points: String
    let isYou: Bool
}

struct SettingRow: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let value: String
}

struct ArtistSubmission: Identifiable, Equatable {
    let id: String
    let serial: String
    let handle: String
    let meta: String
    let owedCents: Int
}

enum Verdict: Equatable { case approved, disputed }

// What TikTok will let this creator post — surfaced before composing, as the
// Content Posting API requires. `directPostEnabled` is false until TikTok's
// app audit clears, and the app keeps the paste-a-link path until it does.
struct CreatorInfo: Equatable {
    let nickname: String
    let privacyOptions: [String]
    let maxDurationSec: Int
    let directPostEnabled: Bool
}

enum DirectPostOutcome: Equatable {
    case processing
    case posted(checksPassed: Bool)
}

enum PayoutModel: Int, CaseIterable {
    case perViews = 0, perClip = 1
    var label: String { self == .perViews ? "Per 100k views" : "Per clip" }
    var rateLabel: String { self == .perViews ? "$5 / 5,000 views" : "$20 / approved clip" }
}

// A clip in the Stage feed. Bounty-scoped and first-party: every one of these
// was submitted to a contract by a clipper who connected their TikTok account,
// which is what keeps the feed clear of Developer Terms §III.3(p) — it's a
// review surface for our own marketplace, not a replica of the For-You page.
// See docs/skins/FEASIBILITY.md §3.
struct StageClip: Identifiable, Equatable {
    let id: String          // our submission id
    let videoID: String     // TikTok video id — drives the embed player URL
    let handle: String
    let serial: String
    let views: String

    // Official embed player, unmodified, one post per frame. Chrome is hidden
    // through documented query parameters only.
    var embedURL: URL? {
        URL(string: "https://www.tiktok.com/player/v1/\(videoID)"
            + "?autoplay=0&controls=0&progress_bar=0&description=0"
            + "&music_info=0&rel=0&native_context_menu=0&closed_caption=0")
    }
}
