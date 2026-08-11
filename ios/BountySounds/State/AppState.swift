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
        checklistDone = [true, false, false, false]
        Task { try? await api.claimBounty(id: bounty.id) }
        flash("Claim held for 6 days. Checklist is on your desk.", goTo: .claims)
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

    func sendAppeal() {
        Task { try? await api.sendAppeal(statement: "") }
        screen = .claims
    }

    // -- artist mode ----------------------------------------------------------

    func fundPurse() {
        Task {
            do {
                let clientSecret = try await api.postBounty(
                    purseCents: purseSelection * 100, model: payoutModel)
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
