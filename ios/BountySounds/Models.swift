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

enum PayoutModel: Int, CaseIterable {
    case perViews = 0, perClip = 1
    var label: String { self == .perViews ? "Per 100k views" : "Per clip" }
    var rateLabel: String { self == .perViews ? "$5 / 5,000 views" : "$20 / approved clip" }
}
