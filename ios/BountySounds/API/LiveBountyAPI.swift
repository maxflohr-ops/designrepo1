import Foundation

// URLSession implementation of BountyAPI against the backend's /v1 REST
// surface. Swap it in from BountySoundsApp:
//
//   AppState(api: LiveBountyAPI(baseURL: URL(string: "https://api.bountysounds.com")!,
//                               token: sessionToken))
//
// Every mutating call carries an Idempotency-Key. Reads that have no server
// endpoint yet (roster, settings, static contract terms) fall back to local
// values — tracked in docs/LAUNCH.md.
struct LiveBountyAPI: BountyAPI {
    let baseURL: URL
    let token: String
    private let cache = ClaimCache()
    private let fallback = MockBountyAPI()

    // MARK: transport

    private func request(_ method: String, _ path: String,
                         body: [String: Any]? = nil,
                         idempotent: Bool = false) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if idempotent { req.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        }
        return data
    }

    private func json(_ data: Data) throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    enum APIError: Error { case http(Int, Data) }

    // MARK: formatting

    private func dollars(_ cents: Int) -> String {
        "$\((cents / 100).formatted())"
    }

    private func rateLabel(model: String, rateCents: Int, rateUnit: Int) -> String {
        model == "per_clip"
            ? "\(dollars(rateCents)) per approved clip"
            : "\(dollars(rateCents)) per \(rateUnit.formatted()) views"
    }

    private func shortDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: board

    func fetchBoard() async throws -> [Bounty] {
        let body = try json(try await request("GET", "v1/board?limit=25"))
        let rows = body["bounties"] as? [[String: Any]] ?? []
        var bounties: [Bounty] = []
        for r in rows {
            let id = r["id"] as? String ?? ""
            let slotCap = r["slot_cap"] as? Int ?? 0
            let claimed = r["claimed_slots"] as? Int ?? 0
            bounties.append(Bounty(
                id: id,
                serial: r["serial"] as? String ?? "",
                purse: dollars(r["purse_cents"] as? Int ?? 0),
                title: r["title"] as? String ?? "",
                song: r["sound_title"] as? String ?? "",
                brief: r["brief"] as? String ?? "",
                rate: rateLabel(model: r["payout_model"] as? String ?? "per_view",
                                rateCents: r["rate_cents"] as? Int ?? 0,
                                rateUnit: r["rate_unit"] as? Int ?? 1),
                platform: r["platform"] as? String ?? "tiktok",
                deadline: shortDate(r["deadline_at"] as? String ?? ""),
                slots: claimed == 0 ? "open" : "\(claimed) of \(slotCap) claimed"
            ))
        }
        return bounties
    }

    func fetchCaptured(bountyId: String) async throws -> [CapturedClip] {
        let body = try json(try await request("GET", "v1/bounties/\(bountyId)"))
        let rows = body["captured"] as? [[String: Any]] ?? []
        return rows.map { r in
            CapturedClip(
                id: r["id"] as? String ?? UUID().uuidString,
                serial: r["tiktok_video_id"] as? String ?? "",
                handle: r["handle"] as? String ?? "",
                views: "\(((r["views"] as? Int ?? 0) / 1000))k",
                paid: dollars(r["accrued_cents"] as? Int ?? 0)
            )
        }
    }

    // Reuses the bounty detail payload — the Stage feed is the same captured
    // submissions, rendered as an embed pager instead of a table. Clips whose
    // TikTok video id we never resolved are skipped rather than shown broken.
    func fetchStageClips(bountyId: String) async throws -> [StageClip] {
        let body = try json(try await request("GET", "v1/bounties/\(bountyId)"))
        let rows = body["captured"] as? [[String: Any]] ?? []
        let clips: [StageClip] = rows.enumerated().compactMap { index, r in
            guard let videoID = r["tiktok_video_id"] as? String, !videoID.isEmpty else { return nil }
            return StageClip(
                id: r["id"] as? String ?? videoID,
                videoID: videoID,
                handle: r["handle"] as? String ?? "",
                serial: String(format: "%@ %02d", bountyId.uppercased(), index + 1),
                views: "\(((r["views"] as? Int ?? 0) / 1000))k"
            )
        }
        return clips
    }

    // Contract terms are product copy, not server data.
    func fetchContractRules(bountyId: String) async throws -> [String] {
        try await fallback.fetchContractRules(bountyId: bountyId)
    }

    // MARK: claims

    func claimBounty(id: String) async throws {
        let body = try json(try await request("POST", "v1/bounties/\(id)/claims", idempotent: true))
        if let claim = body["claim"] as? [String: Any], let claimId = claim["id"] as? String {
            await cache.setClaim(claimId, forBounty: id)
        }
    }

    private func claimId(forBounty bountyId: String) async throws -> String? {
        if let cached = await cache.claim(forBounty: bountyId) { return cached }
        let body = try json(try await request("GET", "v1/me/claims"))
        for r in body["claims"] as? [[String: Any]] ?? [] {
            if r["bounty_id"] as? String == bountyId, r["state"] as? String == "open",
               let id = r["id"] as? String {
                await cache.setClaim(id, forBounty: bountyId)
                return id
            }
        }
        return nil
    }

    func updateChecklist(bountyId: String, done: [Bool]) async throws {
        guard let claimId = try await claimId(forBounty: bountyId) else { return }
        _ = try await request("PATCH", "v1/claims/\(claimId)", body: ["checklist": done])
    }

    func lodgeSubmission(bountyId: String, videoURL: String) async throws -> [SubmissionCheck] {
        guard let claimId = try await claimId(forBounty: bountyId) else {
            throw APIError.http(404, Data())
        }
        let body = try json(try await request(
            "POST", "v1/claims/\(claimId)/submission",
            body: ["tiktokVideoId": videoURL], idempotent: true))
        let checks = body["checks"] as? [String: Bool] ?? [:]
        let order: [(String, String)] = [
            ("sound_match", "Sound matches the contract"),
            ("posted_in_window", "Posted inside the window"),
            ("handle_verified", "Account handle verified"),
            ("duplicate_clear", "Duplicate check"),
        ]
        return order.map { key, title in
            let passed = checks[key] ?? false
            return SubmissionCheck(title: title, state: passed ? "passed" : "failed", passed: passed)
        }
    }

    func fetchChecklistSteps() async throws -> [ChecklistStep] {
        try await fallback.fetchChecklistSteps() // product copy
    }

    // MARK: direct post

    func fetchCreatorInfo() async throws -> CreatorInfo? {
        let body = try json(try await request("GET", "v1/me/tiktok/creator-info"))
        guard let creator = body["creator"] as? [String: Any] else { return nil }
        return CreatorInfo(
            nickname: creator["nickname"] as? String ?? "",
            privacyOptions: creator["privacyOptions"] as? [String] ?? [],
            maxDurationSec: creator["maxVideoDurationSec"] as? Int ?? 0,
            directPostEnabled: body["directPostEnabled"] as? Bool ?? false
        )
    }

    // init → PUT the bytes straight to TikTok → poll until it's live. The
    // video never touches our servers.
    func directPost(bountyId: String, video: Data, caption: String, privacyLevel: String) async throws -> DirectPostOutcome {
        guard let claimId = try await claimId(forBounty: bountyId) else {
            throw APIError.http(404, Data())
        }
        let start = try json(try await request(
            "POST", "v1/claims/\(claimId)/direct-post",
            body: ["caption": caption, "privacyLevel": privacyLevel, "videoSizeBytes": video.count],
            idempotent: true))
        if let uploadURLString = start["uploadUrl"] as? String,
           let uploadURL = URL(string: uploadURLString) {
            var put = URLRequest(url: uploadURL)
            put.httpMethod = "PUT"
            put.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
            put.setValue("bytes 0-\(video.count - 1)/\(video.count)", forHTTPHeaderField: "Content-Range")
            let (_, response) = try await URLSession.shared.upload(for: put, from: video)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, Data())
            }
        }
        // TikTok encodes asynchronously; poll while it does.
        for _ in 0..<40 {
            let status = try json(try await request("POST", "v1/claims/\(claimId)/direct-post/status"))
            if status["state"] as? String == "posted" {
                let state = (status["submission"] as? [String: Any])?["state"] as? String
                return .posted(checksPassed: state == "counting")
            }
            try await Task.sleep(for: .seconds(3))
        }
        return .processing
    }

    func fetchReviewing() async throws -> [ReviewingClaim] {
        let body = try json(try await request("GET", "v1/me/claims"))
        var out: [ReviewingClaim] = []
        for r in body["claims"] as? [[String: Any]] ?? [] {
            guard let subState = r["submission_state"] as? String else { continue }
            let title = r["title"] as? String ?? ""
            let accrued = dollars(r["accrued_cents"] as? Int ?? 0)
            switch subState {
            case "held":
                if let disputeId = r["dispute_id"] as? String { await cache.setDispute(disputeId) }
                out.append(ReviewingClaim(id: r["id"] as? String ?? "", title: title,
                                          meta: "\(accrued) held", state: "disputed"))
            case "paid", "payable":
                out.append(ReviewingClaim(id: r["id"] as? String ?? "", title: title,
                                          meta: "\(accrued) cleared", state: "approved"))
            default: continue
            }
        }
        return out
    }

    func fetchEvidence() async throws -> [EvidenceRow] {
        try await fallback.fetchEvidence() // evidence upload UI lands with the appeal flow
    }

    func sendAppeal(statement: String) async throws {
        guard let disputeId = await cache.dispute() else { return }
        _ = try await request("POST", "v1/disputes/\(disputeId)/appeal",
                              body: ["statement": statement, "evidence": []], idempotent: true)
    }

    // MARK: purse

    func fetchPurse() async throws -> (payable: String, pending: String, lifetime: String) {
        let body = try json(try await request("GET", "v1/me/purse"))
        return (
            dollars(body["payableCents"] as? Int ?? 0),
            "\(dollars(body["pendingCents"] as? Int ?? 0)) pending views",
            "\(dollars(body["lifetimeCents"] as? Int ?? 0)) paid to date"
        )
    }

    func fetchLedger() async throws -> [LedgerRow] {
        let body = try json(try await request("GET", "v1/me/purse"))
        let rows = body["feed"] as? [[String: Any]] ?? []
        return rows.enumerated().map { index, r in
            let kind = r["kind"] as? String ?? ""
            let cents = r["amount_cents"] as? Int ?? 0
            let credit = r["direction"] as? String == "credit"
            let title = r["bounty_title"] as? String ?? (kind == "cash_out" ? "Cash out" : kind)
            let tone: LedgerRow.Tone = kind == "cash_out" ? .debit
                : (r["submission_state"] as? String == "held" ? .held : .credit)
            let sign = tone == .debit ? "−" : (tone == .held ? "" : "+")
            return LedgerRow(id: "\(index)", title: title,
                             meta: shortDate(r["created_at"] as? String ?? ""),
                             amount: "\(sign)\(dollars(cents))",
                             tone: credit ? tone : .debit)
        }
    }

    func cashOut() async throws {
        let purse = try json(try await request("GET", "v1/me/purse"))
        let amount = purse["payableCents"] as? Int ?? 0
        guard amount > 0 else { throw APIError.http(422, Data()) }
        let attestation = await DeviceTrust.attestationHeader(baseURL: baseURL, token: token)
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/me/payouts"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        req.setValue(attestation, forHTTPHeaderField: "X-Device-Attestation")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["amountCents": amount])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        }
    }

    // MARK: wire / roster / settings

    func fetchWire() async throws -> [WireItem] {
        let body = try json(try await request("GET", "v1/me/wire"))
        let rows = body["items"] as? [[String: Any]] ?? []
        return rows.map { r in
            let tone: WireItem.Tone = switch (r["tone"] as? String) ?? "" {
            case "money": .money
            case "warn": .warn
            default: .info
            }
            return WireItem(id: r["id"] as? String ?? UUID().uuidString,
                            body: r["body"] as? String ?? "",
                            when: shortDate(r["created_at"] as? String ?? ""),
                            unread: r["read_at"] == nil || r["read_at"] is NSNull,
                            tone: tone)
        }
    }

    func fetchRoster() async throws -> [RosterRow] {
        let body = try json(try await request("GET", "v1/roster"))
        let rows = body["roster"] as? [[String: Any]] ?? []
        return rows.map { r in
            let handle = r["handle"] as? String ?? ""
            let isYou = r["isYou"] as? Bool ?? false
            let views = r["paid_views"] as? Int ?? 0
            let viewsLabel = views >= 1_000_000
                ? String(format: "%.1fm", Double(views) / 1_000_000)
                : "\(views / 1000)k"
            return RosterRow(
                id: r["id"] as? String ?? UUID().uuidString,
                rank: String(format: "%02d", r["rank"] as? Int ?? 0),
                initials: String(handle.prefix(2)).uppercased(),
                handle: isYou ? "\(handle) · you" : handle,
                meta: "\(viewsLabel) paid views · \(r["bounties"] as? Int ?? 0) bounties",
                points: (r["points"] as? Int ?? 0).formatted(),
                isYou: isYou
            )
        }
    }

    func fetchSettings() async throws -> [SettingRow] {
        try await fallback.fetchSettings() // device-local prefs + account basics
    }

    // MARK: artist

    func fetchArtistSubmissions() async throws -> [ArtistSubmission] {
        let body = try json(try await request("GET", "v1/me/review"))
        let rows = body["submissions"] as? [[String: Any]] ?? []
        return rows.map { r in
            ArtistSubmission(
                id: r["id"] as? String ?? "",
                serial: r["serial"] as? String ?? "",
                handle: r["handle"] as? String ?? "",
                meta: "posted \(shortDate(r["posted_at"] as? String ?? "")) · \(((r["views"] as? Int ?? 0) / 1000))k views",
                owedCents: r["accrued_cents"] as? Int ?? 0
            )
        }
    }

    func submitVerdict(submissionId: String, verdict: Verdict) async throws {
        _ = try await request("POST", "v1/submissions/\(submissionId)/verdict",
                              body: ["verdict": verdict == .approved ? "approve" : "dispute"],
                              idempotent: true)
    }

    func postBounty(purseCents: Int, model: PayoutModel, soundURL: String) async throws -> String? {
        let resolved = try json(try await request("POST", "v1/sounds/resolve", body: ["url": soundURL]))
        guard let sound = resolved["sound"] as? [String: Any], let soundId = sound["id"] as? String else {
            throw APIError.http(422, Data())
        }
        let title = (sound["title"] as? String).flatMap { $0 == "Untitled sound" ? nil : "Clip \u{201C}\($0)\u{201D}" }
        let body = try json(try await request("POST", "v1/bounties", body: [
            "soundId": soundId,
            "title": title ?? "New sound bounty",
            "payoutModel": model == .perClip ? "per_clip" : "per_view",
            "rateCents": model == .perClip ? 2000 : 500,
            "rateUnit": 5000,
            "purseCents": purseCents,
            "deadlineAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(14 * 86400)),
        ], idempotent: true))
        return body["clientSecret"] as? String
    }

    func topUpPurse(bountyId: String, amountCents: Int) async throws -> String? {
        let body = try json(try await request("POST", "v1/bounties/\(bountyId)/topups",
                                              body: ["amountCents": amountCents], idempotent: true))
        return body["clientSecret"] as? String
    }

    func payoutOnboardingLink() async throws -> URL? {
        let body = try json(try await request("POST", "v1/me/payout-account", idempotent: true))
        return (body["onboardingUrl"] as? String).flatMap(URL.init(string:))
    }
}

// Claim/dispute id bookkeeping across screens.
private actor ClaimCache {
    private var claimByBounty: [String: String] = [:]
    private var openDisputeId: String?

    func setClaim(_ claimId: String, forBounty bountyId: String) { claimByBounty[bountyId] = claimId }
    func claim(forBounty bountyId: String) -> String? { claimByBounty[bountyId] }
    func setDispute(_ id: String) { openDisputeId = id }
    func dispute() -> String? { openDisputeId }
}
