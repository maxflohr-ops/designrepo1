import Foundation

// Fixture data lifted verbatim from BountyApp.dc.html so the app demos
// exactly like the design prototype.
struct MockBountyAPI: BountyAPI {

    func fetchBoard() async throws -> [Bounty] {
        [
            Bounty(id: "b141", serial: "B 00000141 ★", purse: "$500",
                   title: "Clip the Thursday stream", song: "Northsider — Ridge Club",
                   brief: "Best 20 seconds of the Thursday broadcast. Sound must be the listed audio, no re-uploads, caption free.",
                   rate: "$5 per 5,000 views", platform: "tiktok", deadline: "Aug 21", slots: "3 of 12 claimed"),
            Bounty(id: "b139", serial: "B 00000139", purse: "$400",
                   title: "Hook challenge — new single", song: "Biting Bullets — Ridge Club",
                   brief: "Cut to the hook at 0:42. Any format, any face. First fifteen approved clips take the purse.",
                   rate: "$20 per approved clip", platform: "tiktok", deadline: "Aug 18", slots: "9 of 15 claimed"),
            Bounty(id: "b136", serial: "B 00000136", purse: "$1,200",
                   title: "Keynote pull-quotes", song: "Founders' Day keynote",
                   brief: "Pull the three sharpest lines from the ninety-minute keynote. Captions welcome, no music bed.",
                   rate: "$8 per 10,000 views", platform: "shorts", deadline: "Sep 02", slots: "1 of 20 claimed"),
            Bounty(id: "b131", serial: "B 00000131", purse: "$260",
                   title: "Podcast cold opens", song: "The Long Way Round ep. 118",
                   brief: "Thirty seconds that make someone press play on the full episode. Vertical only.",
                   rate: "$12 per approved clip", platform: "tiktok", deadline: "Aug 30", slots: "open"),
        ]
    }

    func fetchCaptured(bountyId: String) async throws -> [CapturedClip] {
        [
            CapturedClip(id: "c1", serial: "B 141 · 01", handle: "merrowcuts", views: "412k", paid: "$412"),
            CapturedClip(id: "c2", serial: "B 141 · 02", handle: "halfstep", views: "88k", paid: "$88"),
            CapturedClip(id: "c3", serial: "B 139 · 07", handle: "novaedits", views: "1.2m", paid: "$240"),
            CapturedClip(id: "c4", serial: "B 136 · 03", handle: "quietfrog", views: "56k", paid: "$44"),
        ]
    }

    func fetchContractRules(bountyId: String) async throws -> [String] {
        [
            "Use the listed sound. A re-upload of the audio does not count.",
            "Post within the claim window or the slot returns to the board.",
            "Views are read from the public TikTok counter at day 14.",
            "One submission per claim. Reclaim for a second clip.",
            "Deleted posts void the claim, even after approval.",
        ]
    }

    func claimBounty(id: String) async throws {}
    func updateChecklist(bountyId: String, done: [Bool]) async throws {}

    func lodgeSubmission(bountyId: String, videoURL: String) async throws -> [SubmissionCheck] {
        [
            SubmissionCheck(title: "Sound matches the contract", state: "passed", passed: true),
            SubmissionCheck(title: "Posted inside the window", state: "passed", passed: true),
            SubmissionCheck(title: "Account handle verified", state: "@merrowcuts", passed: nil),
            SubmissionCheck(title: "Duplicate check", state: "clear", passed: true),
        ]
    }

    func fetchChecklistSteps() async throws -> [ChecklistStep] {
        [
            ChecklistStep(id: 0, title: "Contract terms read", subtitle: "rate, window, and cap accepted"),
            ChecklistStep(id: 1, title: "Sound saved to TikTok", subtitle: "open the sound page and tap Add to favourites"),
            ChecklistStep(id: 2, title: "Clip cut and exported", subtitle: "vertical, under 60s, original audio"),
            ChecklistStep(id: 3, title: "Posted to TikTok", subtitle: "then lodge the link here"),
        ]
    }

    func fetchReviewing() async throws -> [ReviewingClaim] {
        [
            ReviewingClaim(id: "r1", title: "Hook challenge — new single",
                           meta: "posted Aug 04 · 88k views held", state: "disputed"),
            ReviewingClaim(id: "r2", title: "Podcast cold opens",
                           meta: "posted Jul 28 · window closed", state: "approved"),
        ]
    }

    func fetchEvidence() async throws -> [EvidenceRow] {
        [
            EvidenceRow(title: "Screen recording of the sound page", value: "attached"),
            EvidenceRow(title: "Original export, 0:19", value: "attached"),
            EvidenceRow(title: "Post timestamp", value: "Aug 04 · 18:22"),
        ]
    }

    func sendAppeal(statement: String) async throws {}

    func fetchPurse() async throws -> (payable: String, pending: String, lifetime: String) {
        ("$248", "$96 pending views", "$1,410 paid to date")
    }

    func fetchLedger() async throws -> [LedgerRow] {
        [
            LedgerRow(id: "l1", title: "Clip the Thursday stream", meta: "412k views · cleared Aug 06", amount: "+$412", tone: .credit),
            LedgerRow(id: "l2", title: "Hook challenge — new single", meta: "held · appeal open", amount: "$88", tone: .held),
            LedgerRow(id: "l3", title: "Cash out to PayPal", meta: "Aug 01", amount: "−$600", tone: .debit),
            LedgerRow(id: "l4", title: "Keynote pull-quotes", meta: "56k views · cleared Jul 24", amount: "+$44", tone: .credit),
            LedgerRow(id: "l5", title: "Podcast cold opens", meta: "approved Jul 20", amount: "+$36", tone: .credit),
        ]
    }

    func cashOut() async throws {}

    func fetchWire() async throws -> [WireItem] {
        [
            WireItem(id: "w1", body: "New purse on a sound you clip — $500 on Northsider.", when: "12 minutes ago", unread: true, tone: .money),
            WireItem(id: "w2", body: "Your clip cleared. $412 is payable.", when: "2 hours ago", unread: true, tone: .money),
            WireItem(id: "w3", body: "Claim on B 00000139 expires in 24 hours.", when: "yesterday", unread: false, tone: .warn),
            WireItem(id: "w4", body: "Ridge Club topped up the purse to $500.", when: "2 days ago", unread: false, tone: .info),
            WireItem(id: "w5", body: "You moved to rank 014 on the roster.", when: "4 days ago", unread: false, tone: .info),
        ]
    }

    func fetchRoster() async throws -> [RosterRow] {
        [
            RosterRow(id: "n1", rank: "01", initials: "NV", handle: "novaedits", meta: "4.2m paid views · 18 bounties", points: "8,410", isYou: false),
            RosterRow(id: "n2", rank: "02", initials: "HS", handle: "halfstep", meta: "3.1m paid views · 22 bounties", points: "6,220", isYou: false),
            RosterRow(id: "n3", rank: "03", initials: "QF", handle: "quietfrog", meta: "2.8m paid views · 11 bounties", points: "5,640", isYou: false),
            RosterRow(id: "n4", rank: "04", initials: "DR", handle: "drywall", meta: "2.2m paid views · 31 bounties", points: "4,180", isYou: false),
            RosterRow(id: "n5", rank: "12", initials: "SB", handle: "softboil", meta: "1.4m paid views · 9 bounties", points: "2,010", isYou: false),
            RosterRow(id: "n6", rank: "13", initials: "LT", handle: "lateswitch", meta: "1.3m paid views · 14 bounties", points: "1,880", isYou: false),
            RosterRow(id: "n7", rank: "14", initials: "MW", handle: "merrowcuts · you", meta: "1.1m paid views · 7 bounties", points: "1,240", isYou: true),
            RosterRow(id: "n8", rank: "15", initials: "PN", handle: "pinecut", meta: "980k paid views · 12 bounties", points: "1,120", isYou: false),
        ]
    }

    func fetchSettings() async throws -> [SettingRow] {
        [
            SettingRow(title: "TikTok account", value: "@merrowcuts"),
            SettingRow(title: "Push alerts", value: "new purses"),
            SettingRow(title: "Payout method", value: "PayPal"),
            SettingRow(title: "Face ID for cash-out", value: "on"),
            SettingRow(title: "Taste profile", value: "retune"),
            SettingRow(title: "The roster", value: "rank 014"),
            SettingRow(title: "Sign out", value: ""),
        ]
    }

    func fetchArtistSubmissions() async throws -> [ArtistSubmission] {
        [
            ArtistSubmission(id: "s1", serial: "B 141 · 04", handle: "merrowcuts", meta: "posted Aug 06 · 412k views", owedCents: 41_200),
            ArtistSubmission(id: "s2", serial: "B 141 · 05", handle: "halfstep", meta: "posted Aug 07 · 88k views", owedCents: 8_800),
            ArtistSubmission(id: "s3", serial: "B 141 · 06", handle: "quietfrog", meta: "posted Aug 08 · 12k views", owedCents: 1_200),
        ]
    }

    func submitVerdict(submissionId: String, verdict: Verdict) async throws {}
    func postBounty(purseCents: Int, model: PayoutModel) async throws -> String? { nil }
    func topUpPurse(bountyId: String, amountCents: Int) async throws -> String? { nil }
    func payoutOnboardingLink() async throws -> URL? { nil }
}
