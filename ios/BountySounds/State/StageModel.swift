import SwiftUI

// Split bounds. Below ~0.30 the skin is unusable; above ~0.62 the clip stops
// reading as video and starts reading as a thumbnail. Kept out of StageModel
// so `init`'s default argument doesn't reach into main-actor-isolated state
// from a nonisolated context.
enum StageSplit {
    static let minRatio = 0.30
    static let maxRatio = 0.62
    static let defaultRatio = 0.46
    static let range = minRatio...maxRatio
}

// The Stage: a bounty's clip feed on the bottom, a skin on top, one split.
// Owns the feed cursor, the split ratio, and the dwell accounting that feeds
// AttentionRecorder — the skin views read this and never talk to the API.
@MainActor
final class StageModel: ObservableObject {
    @Published var clips: [StageClip] = []
    @Published var index = 0 { didSet { advanced(from: oldValue) } }
    @Published var skinID: String { didSet { switched(from: oldValue) } }
    @Published var splitRatio: Double   // fraction of stage height given to the skin
    @Published var loading = true
    @Published var marked: Set<String> = []

    let bounty: Bounty?
    private let api: BountyAPI
    private let attention: AttentionRecorder
    private var clipStart = Date()

    init(bounty: Bounty?, api: BountyAPI, attention: AttentionRecorder,
         skinID: String = "tally", splitRatio: Double = StageSplit.defaultRatio) {
        self.bounty = bounty
        self.api = api
        self.attention = attention
        self.skinID = skinID
        self.splitRatio = splitRatio.clamped(to: StageSplit.range)
    }

    var current: StageClip? { clips.indices.contains(index) ? clips[index] : nil }
    var bountyID: String { bounty?.id ?? "" }
    var descriptor: SkinDescriptor { SkinCatalog.descriptor(id: skinID) }

    func load() async {
        loading = true
        clips = (try? await api.fetchStageClips(bountyId: bountyID)) ?? []
        loading = false
        clipStart = Date()
        attention.stageOpen(bountyID: bountyID, skinID: skinID, ratio: splitRatio)
    }

    func close() {
        flushCurrentClip()
        attention.stageClose()
    }

    func setRatio(_ ratio: Double) {
        let clamped = ratio.clamped(to: StageSplit.range)
        guard abs(clamped - splitRatio) > 0.001 else { return }
        splitRatio = clamped
    }

    // Called on drag end, not per frame — a gesture would otherwise emit
    // hundreds of split_change events for one adjustment.
    func commitRatio() {
        attention.splitChange(ratio: splitRatio)
    }

    func record(_ action: SkinAction) {
        attention.skinInteraction(skinID: skinID, action: action)
    }

    func toggleMark(_ clipID: String) {
        if marked.contains(clipID) { marked.remove(clipID) } else { marked.insert(clipID) }
        record(.mark)
    }

    // MARK: - Dwell

    private func advanced(from previous: Int) {
        guard previous != index else { return }
        flushCurrentClip(at: previous)
        clipStart = Date()
    }

    private func switched(from previous: String) {
        guard previous != skinID else { return }
        // Close the clip out under the old skin before attributing it to the new
        // one — the whole point of the report is which skin held the attention.
        flushCurrentClip(skinID: previous)
        clipStart = Date()
        attention.skinSwitch(from: previous, to: skinID)
    }

    private func flushCurrentClip(at position: Int? = nil, skinID: String? = nil) {
        let slot = position ?? index
        guard clips.indices.contains(slot) else { return }
        let dwellMs = Int(Date().timeIntervalSince(clipStart) * 1000)
        guard dwellMs > 250 else { return }   // drop scroll-through frames
        attention.clipImpression(
            clipID: clips[slot].id,
            bountyID: bountyID,
            skinID: skinID ?? self.skinID,
            dwellMs: dwellMs,
            // Proxy until the embed player's onStateChange is wired through
            // postMessage — see ClipFeedView. Eight seconds is roughly a loop
            // on the clip lengths this board carries.
            completed: dwellMs >= 8_000,
            ratio: splitRatio
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
