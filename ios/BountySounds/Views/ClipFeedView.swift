import SwiftUI
import WebKit

// The bottom half of the Stage: a vertical pager over the clips submitted to
// one bounty.
//
// Scope matters here and it is not an accident. This is bounty-scoped, drawn
// from submissions by clippers who connected their own TikTok account and sent
// us the clip on purpose, rendered through the official embed player with only
// documented query parameters. It is a review surface for our own marketplace.
// A general, infinite, algorithmic feed of TikTok content would be the thing
// Developer Terms §III.3(p) calls replicating a TikTok Service — see
// docs/skins/FEASIBILITY.md §3 before anyone widens this.
struct ClipFeedView: View {
    @EnvironmentObject var stage: StageModel
    @State private var visibleID: String?

    var body: some View {
        GeometryReader { geo in
            content(height: geo.size.height)
        }
        .background(Color.ink)
    }

    @ViewBuilder
    private func content(height: CGFloat) -> some View {
        if stage.loading {
            placeholder(text: "Loading the feed")
        } else if stage.clips.isEmpty {
            placeholder(text: "No clips captured on this contract yet")
        } else {
            pager(height: height)
        }
    }

    private func pager(height: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(stage.clips) { clip in
                    ClipPane(clip: clip)
                        .frame(height: height)
                        .id(clip.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleID)
        .onAppear { visibleID = stage.clips.first?.id }
        .onChange(of: visibleID) { _, id in
            guard let id, let position = stage.clips.firstIndex(where: { $0.id == id }) else { return }
            stage.index = position
        }
    }

    private func placeholder(text: String) -> some View {
        VStack {
            Spacer()
            MonoLabel(text: text, size: 10, tracking: 0.18, color: Color.paper.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// One clip. A configured build loads the real embed player; the offline
// prototype shows the submission card instead, so the demo never depends on
// network or on fixture video ids resolving.
private struct ClipPane: View {
    let clip: StageClip

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if AppConfig.isLive, let url = clip.embedURL {
                EmbedPlayer(url: url)
            } else {
                fixturePane
            }
            caption
        }
        .clipped()
    }

    private var fixturePane: some View {
        ZStack {
            Color.ink
            VStack(spacing: 10) {
                MonoLabel(text: "▶", size: 22, tracking: 0, color: Color.paper.opacity(0.35), bold: true)
                MonoLabel(text: "Embed player — configured builds only",
                          size: 9, tracking: 0.16, color: Color.paper.opacity(0.45))
            }
        }
    }

    private var caption: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("@\(clip.handle)")
                .font(.grotesk(13.5, .medium))
                .foregroundStyle(Color.paper)
            MonoLabel(text: clip.views, size: 9, tracking: 0.16, color: Color.paper.opacity(0.7))
            Spacer()
            MonoLabel(text: clip.serial, size: 9, tracking: 0.16, color: Color.paper.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.clear, Color.ink.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }
}

// TikTok's embed player in a web view. Inline playback and a muted autoplay
// policy are both required or iOS refuses to start the video without a tap;
// vertical scrolling is disabled inside the frame so the pager owns the gesture.
//
// Not wired yet: the player's postMessage channel (`onStateChange`) would give
// real completion instead of StageModel's dwell-time proxy.
private struct EmbedPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard web.url != url else { return }
        web.load(URLRequest(url: url))
    }
}
