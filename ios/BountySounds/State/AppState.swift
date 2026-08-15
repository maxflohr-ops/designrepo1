import SwiftUI
import UIKit

enum Screen: Equatable {
    case onboard, board, detail, claims, dispute, submit, purse, alerts, me, roster, post, review
}

enum Mode { case clipper, artist }

// Mirrors the prototype's logic class: screen enum, mode, current bounty
// index, detail pager index, checklist booleans, submission verdicts map,
// purse amount + payout model, toast string.
@MainActor
final class AppState: ObservableObject {
    private(set) var api: BountyAPI
    private let tiktokAuth = TikTokAuth()
    @Published var isAuthenticating = false

    @Published var screen: Screen = .onboard
    @Published var mode: Mode = .clipper
    @Published var bountyIndex = 0
    @Published var detailPage = 0
    @Published var checklistDone = [true, false, false, false]
    @Published var verdicts: [String: Verdict] = [:]
    @Published var purseSelection = 500          // dollars, post-flow presets
    @Published var payoutModel: PayoutModel = .perViews
    @Published var soundLink = ""                // pasted TikTok sound URL (artist post flow)
    @Published var toast: String?
    @Published var showShareBanner = true        // deep-linked from the TikTok share sheet

    // fixture-backed data
    @Published var bounties: [Bounty] = []
    @Published var captured: [CapturedClip] = []
    @Published var rules: [String] = []
    @Published var steps: [ChecklistStep] = []
    @Published var reviewing: [ReviewingClaim] = []
    @Published var evidence: [EvidenceRow] = []
    @Published var submissionChecks: [SubmissionCheck] = []
    @Published var ledger: [LedgerRow] = []
    @Published var purseAmounts: (payable: String, pending: String, lifetime: String) = ("$0", "", "")
    @Published var wire: [WireItem] = []
    @Published var roster: [RosterRow] = []
    @Published var settings: [SettingRow] = []
    @Published var artistSubmissions: [ArtistSubmission] = []
    @Published var creatorInfo: CreatorInfo?
    @Published var isPosting = false

    private var toastTask: Task<Void, Never>?

    init(api: BountyAPI? = nil) {
        if let api {
            self.api = api
        } else if AppConfig.isLive, let baseURL = AppConfig.apiBaseURL,
                  let token = Keychain.load(AppConfig.sessionKeychainKey) {
            // restored session: skip onboarding straight to the board
            self.api = LiveBountyAPI(baseURL: baseURL, token: token)
            self.screen = .board
        } else {
            self.api = MockBountyAPI()
        }
        Task { await load() }
    }

    func load() async {
        do {
            bounties = try await api.fetchBoard()
            rules = try await api.fetchContractRules(bountyId: current?.id ?? "")
            captured = try await api.fetchCaptured(bountyId: current?.id ?? "")
            steps = try await api.fetchChecklistSteps()
            reviewing = try await api.fetchReviewing()
            evidence = try await api.fetchEvidence()
            submissionChecks = try await api.lodgeSubmission(bountyId: "", videoURL: "")
            ledger = try await api.fetchLedger()
            purseAmounts = try await api.fetchPurse()
            wire = try await api.fetchWire()
            roster = try await api.fetchRoster()
            settings = try await api.fetchSettings()
            artistSubmissions = try await api.fetchArtistSubmissions()
            creatorInfo = try? await api.fetchCreatorInfo()
        } catch {
            flash("Could not reach the board. Pull to retry.")
        }
    }

    var current: Bounty? {
        bounties.indices.contains(bountyIndex) ? bounties[bountyIndex] : nil
    }

    var showTabs: Bool {
        [.board, .claims, .purse, .alerts, .me, .post, .review, .roster].contains(screen)
    }

    var tabs: [(label: String, screen: Screen)] {
        mode == .artist
            ? [("Bounties", .post), ("Review", .review), ("Purse", .purse), ("Wire", .alerts), ("Desk", .me)]
            : [("Board", .board), ("Claims", .claims), ("Purse", .purse), ("Wire", .alerts), ("Desk", .me)]
    }

    // -- interactions (README "Interactions & Behavior") ----------------------

    func flash(_ message: String, goTo screen: Screen? = nil) {
        toastTask?.cancel()
        if let screen { self.screen = screen }
        toast = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { toast = nil }
        }
    }

    // Onboarding CTAs. In mock mode they jump straight in (the design demo);
    // in live mode they run TikTok Login Kit first.
    func enterClipper() { enter(.clipper) }
    func enterArtist() { enter(.artist) }

    private func enter(_ newMode: Mode) {
        guard AppConfig.isLive else {
            mode = newMode
            screen = newMode == .clipper ? .board : .post
            return
        }
        Task { await signIn(role: newMode) }
    }

    func signIn(role: Mode) async {
        guard let baseURL = AppConfig.apiBaseURL, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let code = try await tiktokAuth.authorize()
            let token = try await TikTokAuth.exchange(
                code: code, role: role == .artist ? "artist" : "clipper", baseURL: baseURL)
            Keychain.save(token, for: AppConfig.sessionKeychainKey)
            api = LiveBountyAPI(baseURL: baseURL, token: token)
            await load()
            mode = role
            screen = role == .clipper ? .board : .post
        } catch {
            flash("TikTok sign-in didn't go through. Try again.")
        }
    }

    func signOut() {
        Keychain.delete(AppConfig.sessionKeychainKey)
        api = MockBountyAPI()
        mode = .clipper
        screen = .onboard
        verdicts = [:]
        checklistDone = [true, false, false, false]
        Task { await load() }
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        screen = newMode == .clipper ? .board : .post  // full app swap, not a filter
    }

    func openBounty(_ index: Int) {
        bountyIndex = index
        detailPage = 0
        screen = .detail
    }

    func seize() {
        guard let bounty = current else { return }
        Task {
            do {
                try await api.claimBounty(id: bounty.id)
                checklistDone = [true, false, false, false]
                flash("Claim held for 6 days. Checklist is on your desk.", goTo: .claims)
            } catch LiveBountyAPI.APIError.http(let status, let data) {
                flash(Self.claimErrorMessage(status: status, data: data))
            } catch {
                flash("You're offline — the claim didn't take. Try again.")
            }
        }
    }

    static func claimErrorMessage(status: Int, data: Data) -> String {
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { $0?["error"] as? String }
        switch code {
        case "slots_full": return "Slots are full — that contract is spoken for."
        case "already_claimed": return "You already hold a claim on this contract."
        case "past_deadline": return "That contract's deadline has passed."
        case "account_floor": return "Your TikTok account is too new to claim yet."
        case "rate_limited": return "Easy — too many claims at once. Try again in a minute."
        default: return status == 409 ? "That contract just closed." : "Couldn't seize it. Try again."
        }
    }

    func cashOut() {
        Task {
            guard AppConfig.isLive else {
                flash("Cash out sent. Face ID confirmed.")
                return
            }
            guard await DeviceTrust.confirmOwner(reason: "Confirm cash-out before money leaves your purse.") else {
                flash("Face ID didn't confirm. Nothing moved.")
                return
            }
            do {
                try await api.cashOut()
                flash("Cash out sent — money's on the way.")
                purseAmounts = (try? await api.fetchPurse()) ?? purseAmounts
                ledger = (try? await api.fetchLedger()) ?? ledger
            } catch LiveBountyAPI.APIError.http(let status, let data) {
                let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0?["error"] as? String }
                switch code {
                case "first_payout_hold":
                    flash("First payouts clear 7 days after settlement — yours is almost ripe.")
                case "attestation_invalid", "attestation_unregistered":
                    flash("This device couldn't be verified. Reinstall from TestFlight and retry.")
                default:
                    flash(status == 422 ? "Nothing payable yet — views are still counting." : "Cash out didn't go through. Try again.")
                }
            } catch {
                flash("Cash out didn't go through. Try again.")
            }
        }
    }

    func toggleStep(_ index: Int) {
        guard checklistDone.indices.contains(index) else { return }
        checklistDone[index].toggle()
        if let bounty = current {
            Task { try? await api.updateChecklist(bountyId: bounty.id, done: checklistDone) }
        }
    }

    var checkProgress: String { "\(checklistDone.filter { $0 }.count) of 4" }

    func finishSubmit() {
        flash("Submission lodged. Views start counting at post time.", goTo: .claims)
    }

    var canPostFromApp: Bool { creatorInfo?.directPostEnabled == true }

    // Publish straight to TikTok: the video id comes back from TikTok itself,
    // so the claim can't be pointed at someone else's clip.
    func postDirectly(video: Data, caption: String) {
        guard let bounty = current, !isPosting else { return }
        isPosting = true
        Task {
            defer { isPosting = false }
            do {
                let privacy = creatorInfo?.privacyOptions.first(where: { $0 == "PUBLIC_TO_EVERYONE" })
                    ?? creatorInfo?.privacyOptions.first ?? "PUBLIC_TO_EVERYONE"
                switch try await api.directPost(
                    bountyId: bounty.id, video: video, caption: caption, privacyLevel: privacy) {
                case .processing:
                    flash("TikTok is still processing the post. We'll lodge it when it lands.")
                case .posted(let checksPassed):
                    if checksPassed {
                        flash("Posted and lodged. Views start counting now.", goTo: .claims)
                    } else {
                        flash("Posted, but the audio isn't the contract's sound — that won't pay.")
                    }
                }
            } catch {
                flash("TikTok wouldn't take that post. Try again, or paste the link instead.")
            }
        }
    }

    func sendAppeal() {
        Task { try? await api.sendAppeal(statement: "") }
        screen = .claims
    }

    // -- artist mode ----------------------------------------------------------

    func fundPurse() {
        if AppConfig.isLive && soundLink.isEmpty {
            flash("Paste the TikTok sound link first — the contract needs its audio.")
            return
        }
        Task {
            do {
                let clientSecret = try await api.postBounty(
                    purseCents: purseSelection * 100, model: payoutModel, soundURL: soundLink)
                if let clientSecret {
                    // live mode: collect payment in PaymentSheet; the bounty
                    // goes live when the webhook lands
                    guard await PurseFunding.present(clientSecret: clientSecret) else {
                        flash("Payment didn't go through. The purse wasn't funded.")
                        return
                    }
                }
                flash("Purse funded. The contract is live on the board.", goTo: .review)
            } catch {
                flash("Couldn't post the bounty. Try again.")
            }
        }
    }

    func openPayoutOnboarding() {
        Task {
            if let url = try? await api.payoutOnboardingLink(), let url {
                await UIApplication.shared.open(url)
            } else {
                flash("Payout methods are managed in live mode.")
            }
        }
    }

    func approve(_ submission: ArtistSubmission) {
        verdicts[submission.id] = .approved
        Task { try? await api.submitVerdict(submissionId: submission.id, verdict: .approved) }
        flash("Paid \(dollars(submission.owedCents)) to @\(submission.handle).")
    }

    func dispute(_ submission: ArtistSubmission) {
        verdicts[submission.id] = .disputed
        Task { try? await api.submitVerdict(submissionId: submission.id, verdict: .disputed) }
        flash("Held @\(submission.handle) — they have 72 hours to appeal.")
    }

    func topUp() {
        Task {
            do {
                let clientSecret = try await api.topUpPurse(bountyId: current?.id ?? "", amountCents: 25_000)
                if let clientSecret {
                    guard await PurseFunding.present(clientSecret: clientSecret) else {
                        flash("Payment didn't go through. The top-up was cancelled.")
                        return
                    }
                }
                purseSelection += 250
                flash("Purse topped up by $250.")
            } catch {
                flash("Couldn't top up the purse. Try again.")
            }
        }
    }

    var pendingReviewCount: Int { artistSubmissions.filter { verdicts[$0.id] == nil }.count }

    var purseLabel: String { dollars(purseSelection * 100) }

    var unspentLabel: String {
        let paid = artistSubmissions
            .filter { verdicts[$0.id] == .approved }
            .reduce(0) { $0 + $1.owedCents }
        return dollars(max(purseSelection * 100 - paid, 0))
    }

    var purseMath: String {
        payoutModel == .perViews
            ? "Buys about \((purseSelection / 5 * 5000 / 1000).formatted())k counted views."
            : "Buys about \(purseSelection / 20) approved clips."
    }

    func dollars(_ cents: Int) -> String { "$\((cents / 100).formatted())" }
}
