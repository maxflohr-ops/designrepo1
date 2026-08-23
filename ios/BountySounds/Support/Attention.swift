import Foundation
import SwiftUI

// First-party attention telemetry for the Stage.
//
// This is the measurement instrument the whole skins thesis rests on: dwell
// time on a specific sound *while a known secondary task is running*. Nobody
// else can produce that number, and it sells back to the artists who already
// fund the purses.
//
// What it deliberately does NOT collect (docs/skins/FEASIBILITY.md §4):
//  - no content, no free text — `action` is a closed enum
//  - no TikTok Information, so nothing here is a derivative of data we license
//    under Developer Terms §II.1 on a non-transferrable basis
//  - no join key to open_id or the user record. `sessionID` is a fresh UUID per
//    stage session and is never persisted alongside identity. The reports are
//    aggregate (n >= 50 per cell), so the join would buy nothing and would drag
//    the whole feature into Apple guideline 5.1.2's consent regime.

struct AttentionEvent: Codable, Equatable, Sendable {
    let type: String
    let at: Date
    let sessionID: String
    var atMs: Int?
    var bountyID: String?
    var clipID: String?
    var skinID: String?
    var fromSkinID: String?
    var toSkinID: String?
    var action: String?
    var dwellMs: Int?
    var durationMs: Int?
    var completed: Bool?
    var clipsSeen: Int?
    var splitRatio: Double?

    enum CodingKeys: String, CodingKey {
        case type, at
        case sessionID = "session_id"
        case atMs = "at_ms"
        case bountyID = "bounty_id"
        case clipID = "clip_id"
        case skinID = "skin_id"
        case fromSkinID = "from_skin_id"
        case toSkinID = "to_skin_id"
        case action
        case dwellMs = "dwell_ms"
        case durationMs = "duration_ms"
        case completed
        case clipsSeen = "clips_seen"
        case splitRatio = "split_ratio"
    }
}

@MainActor
final class AttentionRecorder: ObservableObject {
    // Exposed for the debug overlay and tests; not rendered in release UI.
    @Published private(set) var buffered: [AttentionEvent] = []

    private var sessionID = UUID().uuidString
    private var sessionStart = Date()
    private var clipsSeen = 0
    private let batchCap = 200

    private let poster: (@Sendable ([AttentionEvent]) async -> Void)?

    // Live builds post to /v1/attention/batch; mock builds drop on flush, which
    // is the right behaviour either way — telemetry must never block or fail UI.
    init(poster: (@Sendable ([AttentionEvent]) async -> Void)? = nil) {
        self.poster = poster ?? AttentionRecorder.defaultPoster()
    }

    nonisolated private static func defaultPoster() -> (@Sendable ([AttentionEvent]) async -> Void)? {
        guard let base = AppConfig.apiBaseURL else { return nil }
        return { events in await AttentionRecorder.post(events, to: base) }
    }

    // MARK: - Recording

    func startSession() {
        sessionID = UUID().uuidString
        sessionStart = Date()
        clipsSeen = 0
    }

    func stageOpen(bountyID: String, skinID: String, ratio: Double) {
        startSession()
        record(make("stage_open", bountyID: bountyID, skinID: skinID, splitRatio: ratio))
    }

    func clipImpression(
        clipID: String, bountyID: String, skinID: String,
        dwellMs: Int, completed: Bool, ratio: Double
    ) {
        clipsSeen += 1
        var e = make("clip_impression", bountyID: bountyID, skinID: skinID, splitRatio: ratio)
        e.clipID = clipID
        e.dwellMs = dwellMs
        e.completed = completed
        record(e)
    }

    func skinSwitch(from: String, to: String) {
        var e = make("skin_switch")
        e.fromSkinID = from
        e.toSkinID = to
        record(e)
    }

    func skinInteraction(skinID: String, action: SkinAction) {
        var e = make("skin_interaction", skinID: skinID)
        e.action = action.rawValue
        record(e)
    }

    func splitChange(ratio: Double) {
        record(make("split_change", splitRatio: ratio))
    }

    func stageClose() {
        var e = make("stage_close")
        e.durationMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
        e.clipsSeen = clipsSeen
        record(e)
        flush()
    }

    // MARK: - Delivery

    // Fire-and-forget. Drops the buffer immediately so a slow network can't
    // double-send, and swallows every failure: losing a batch costs one cell of
    // a report, dropping a frame costs the session.
    func flush() {
        guard !buffered.isEmpty else { return }
        let batch = buffered
        buffered = []
        guard let poster else { return }
        Task.detached { await poster(batch) }
    }

    private func record(_ event: AttentionEvent) {
        buffered.append(event)
        if buffered.count >= batchCap { flush() }
    }

    private func make(
        _ type: String, bountyID: String? = nil, skinID: String? = nil, splitRatio: Double? = nil
    ) -> AttentionEvent {
        let now = Date()
        return AttentionEvent(
            type: type, at: now, sessionID: sessionID,
            atMs: Int(now.timeIntervalSince(sessionStart) * 1000),
            bountyID: bountyID, skinID: skinID, splitRatio: splitRatio.map { ($0 * 1000).rounded() / 1000 }
        )
    }

    nonisolated private static func post(_ events: [AttentionEvent], to base: URL) async {
        struct Body: Encodable { let events: [AttentionEvent] }
        var req = URLRequest(url: base.appendingPathComponent("v1/attention/batch"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        if let token = Keychain.load(AppConfig.sessionKeychainKey) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        req.httpBody = try? encoder.encode(Body(events: events))
        _ = try? await URLSession.shared.data(for: req)
    }
}
