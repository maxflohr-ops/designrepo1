import SwiftUI

// The sound-native skin, and the one that earns its dollar on this platform
// specifically: the bounty's lyric sheet with timestamps, so a clipper can mark
// the hook while watching how other people cut it. Marking a line is the
// interaction the attention report cares about most — it's intent, not idle
// dwell.
struct LyricSheetSkin: View {
    @EnvironmentObject var stage: StageModel
    @State private var hookLine: Int?
    @State private var showAll = true

    private var descriptor: SkinDescriptor { SkinCatalog.descriptor(id: "lyrics") }
    private var sheet: LyricSheet { LyricSheet.northsider }
    private var lines: [LyricSheet.Line] {
        showAll ? sheet.lines : sheet.lines.filter(\.isChorus)
    }

    var body: some View {
        SkinFrame(descriptor: descriptor) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Hairline()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in row(line) }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(stage.bounty?.song ?? sheet.title)
                .font(.serif(15, .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Spacer()
            Button {
                showAll.toggle()
                stage.record(.toggle)
            } label: {
                MonoLabel(text: showAll ? "Chorus only" : "Show all",
                          size: 9, tracking: 0.16, color: .crimson)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func row(_ line: LyricSheet.Line) -> some View {
        let isHook = hookLine == line.id
        return Button {
            hookLine = isHook ? nil : line.id
            stage.record(.mark)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                MonoLabel(text: line.timestamp, size: 9, tracking: 0.1,
                          color: isHook ? .paper : .muted)
                    .frame(width: 34, alignment: .leading)
                Text(line.text)
                    .font(.grotesk(14, line.isChorus ? .medium : .regular))
                    .foregroundStyle(isHook ? Color.paper : .bodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(isHook ? Color.crimson : .clear)
        }
        .buttonStyle(.plain)
    }
}

struct LyricSheet {
    struct Line: Identifiable { let id: Int; let timestamp: String; let text: String; let isChorus: Bool }
    let title: String
    let lines: [Line]

    static let northsider = LyricSheet(title: "Northsider — Ridge Club", lines: [
        Line(id: 0, timestamp: "0:04", text: "Came up the north side with my hands in my coat", isChorus: false),
        Line(id: 1, timestamp: "0:09", text: "Nothing in the pockets but the fare and a note", isChorus: false),
        Line(id: 2, timestamp: "0:15", text: "Told myself I'd call when I got somewhere", isChorus: false),
        Line(id: 3, timestamp: "0:21", text: "Still ain't somewhere, still ain't called", isChorus: false),
        Line(id: 4, timestamp: "0:28", text: "So run it back, run it back", isChorus: true),
        Line(id: 5, timestamp: "0:32", text: "Every winter's got a door in it", isChorus: true),
        Line(id: 6, timestamp: "0:38", text: "Run it back, run it back", isChorus: true),
        Line(id: 7, timestamp: "0:42", text: "I was never gonna walk it slow", isChorus: true),
        Line(id: 8, timestamp: "0:49", text: "Bridge lights doing what the bridge lights do", isChorus: false),
        Line(id: 9, timestamp: "0:55", text: "Half the city sleeping, other half like you", isChorus: false),
    ])
}
