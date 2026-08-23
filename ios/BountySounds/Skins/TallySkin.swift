import SwiftUI

// Free skin, and the default. A clipper scouting a bounty wants two things
// while the feed runs: a sense of what's already been captured, and somewhere
// to flag the moments worth cutting. That's the whole skin.
struct TallySkin: View {
    @EnvironmentObject var stage: StageModel

    private var descriptor: SkinDescriptor { SkinCatalog.descriptor(id: "tally") }

    var body: some View {
        SkinFrame(descriptor: descriptor) {
            VStack(alignment: .leading, spacing: 0) {
                counters
                Hairline().padding(.vertical, 12)
                rateLine
                Spacer(minLength: 8)
                markButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }

    private var counters: some View {
        HStack(alignment: .top, spacing: 0) {
            counter(value: "\(stage.index + 1)", of: "\(max(stage.clips.count, 1))", label: "Clip")
            counter(value: "\(stage.marked.count)", of: nil, label: "Marked")
            counter(value: stage.current?.views ?? "—", of: nil, label: "Views")
        }
    }

    private func counter(value: String, of total: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.serif(24, .bold))
                    .foregroundStyle(Color.ink)
                if let total {
                    Text("/\(total)")
                        .font(.mono(11))
                        .foregroundStyle(Color.muted)
                }
            }
            MonoLabel(text: label, size: 9, tracking: 0.18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rateLine: some View {
        VStack(alignment: .leading, spacing: 5) {
            MonoLabel(text: "This contract pays", size: 9, tracking: 0.18)
            Text(stage.bounty?.rate ?? "—")
                .font(.grotesk(14.5, .medium))
                .foregroundStyle(Color.bodyText)
        }
    }

    private var markButton: some View {
        let isMarked = stage.current.map { stage.marked.contains($0.id) } ?? false
        return StampButton(
            title: isMarked ? "Marked" : "Mark this one",
            fill: isMarked ? .olive : .clear,
            textColor: isMarked ? .paper : .ink,
            minHeight: 46,
            fontSize: 12
        ) {
            if let clip = stage.current { stage.toggleMark(clip.id) }
        }
        .disabled(stage.current == nil)
        .opacity(stage.current == nil ? 0.4 : 1)
    }
}
