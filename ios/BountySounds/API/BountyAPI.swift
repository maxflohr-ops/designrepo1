import Foundation

// The app's edge. Screens talk to this protocol only; `MockBountyAPI` serves
// the design-prototype fixtures, and a URLSession implementation against the
// backend's /v1 REST surface slots in behind the same shape (every mutating
// call there carries an Idempotency-Key).
protocol BountyAPI: Sendable {
    func fetchBoard() async throws -> [Bounty]
    func fetchCaptured(bountyId: String) async throws -> [CapturedClip]
    func fetchContractRules(bountyId: String) async throws -> [String]
    // Bounty-scoped clip feed for the Stage (see docs/skins/FEASIBILITY.md §3).
    func fetchStageClips(bountyId: String) async throws -> [StageClip]

    func claimBounty(id: String) async throws
    func updateChecklist(bountyId: String, done: [Bool]) async throws
    func lodgeSubmission(bountyId: String, videoURL: String) async throws -> [SubmissionCheck]
    func fetchChecklistSteps() async throws -> [ChecklistStep]
    // Content Posting API: publish the clip from inside the app so TikTok
    // hands back the video id itself (nil creator info = not available).
    func fetchCreatorInfo() async throws -> CreatorInfo?
    func directPost(bountyId: String, video: Data, caption: String, privacyLevel: String) async throws -> DirectPostOutcome
    func fetchReviewing() async throws -> [ReviewingClaim]
    func fetchEvidence() async throws -> [EvidenceRow]
    func sendAppeal(statement: String) async throws

    func fetchPurse() async throws -> (payable: String, pending: String, lifetime: String)
    func fetchLedger() async throws -> [LedgerRow]
    func cashOut() async throws
    // Stripe Express onboarding URL for the payout method (nil in mock mode).
    func payoutOnboardingLink() async throws -> URL?

    func fetchWire() async throws -> [WireItem]
    func fetchRoster() async throws -> [RosterRow]
    func fetchSettings() async throws -> [SettingRow]

    func fetchArtistSubmissions() async throws -> [ArtistSubmission]
    func submitVerdict(submissionId: String, verdict: Verdict) async throws
    // Both return a Stripe PaymentIntent client secret to confirm in
    // PaymentSheet, or nil when no payment step is needed (mock mode).
    // soundURL is a pasted TikTok sound link, resolved server-side.
    func postBounty(purseCents: Int, model: PayoutModel, soundURL: String) async throws -> String?
    func topUpPurse(bountyId: String, amountCents: Int) async throws -> String?
}
