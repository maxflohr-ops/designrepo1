import SwiftUI

// Screen 3 — back link, title + purse, 3-panel horizontal pager
// (Details / Terms / Captured) with tab underlines and the 320ms
// cubic-bezier(.22,1,.36,1) slide. Sticky footer CTA.
struct BountyDetailView: View {
    @EnvironmentObject var state: AppState
    private let pages = ["Details", "Terms", "Captured"]

    var body: some View {
        VStack(spacing: 0) {
            header
            pager
            footer
        }
        .background(Color.card)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackLink(label: "board") { state.screen = .board }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(state.current?.title ?? "")
                    .font(.fredericka(26))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(2)
                    .frame(maxWidth: 250, alignment: .leading)
                Spacer()
                Text(state.current?.purse ?? "")
                    .font(.fredericka(30))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 12)

            HStack(spacing: 22) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, label in
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.32)) {
                            state.detailPage = index
                        }
                    } label: {
                        VStack(spacing: 9) {
                            Text(label.uppercased())
                                .font(.mono(10))
                                .tracking(1.8)
                                .foregroundStyle(state.detailPage == index ? Color.ink : Color.muted)
                            Rectangle()
                                .fill(state.detailPage == index ? Color.ink : Color.clear)
                                .frame(height: 2)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minHeight: 44, alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.top, 4)
            .overlay(alignment: .bottom) { Hairline() }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .background(Color.paper)
    }

    private var pager: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                detailsPanel.frame(width: geo.size.width)
                termsPanel.frame(width: geo.size.width)
                capturedPanel.frame(width: geo.size.width)
            }
            .offset(x: -CGFloat(state.detailPage) * geo.size.width)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.32), value: state.detailPage)
        }
        .clipped()
    }

    private var detailsPanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(state.current?.brief ?? "")
                    .font(.grotesk(15))
                    .foregroundStyle(Color.bodyText)
                    .lineSpacing(5)

                VStack(spacing: 0) {
                    factRow("purse posted", state.current?.purse ?? "")
                    factRow("rate", state.current?.rate ?? "")
                    factRow("counting window", "14 days from post")
                    factRow("deadline", state.current?.deadline ?? "")
                    factRow("slots", state.current?.slots ?? "")
                    factRow("platform", state.current?.platform ?? "")
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 0) {
                    MonoLabel(text: "The sound", size: 9.5, tracking: 0.2)
                    HStack(spacing: 12) {
                        Text("ART")
                            .font(.mono(9))
                            .tracking(0.9)
                            .foregroundStyle(Color.paper)
                            .frame(width: 48, height: 48)
                            .background(Color.ink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.current?.song ?? "")
                                .font(.grotesk(15, .semibold))
                                .foregroundStyle(Color.ink)
                            Text("tap to preview · 0:24 of the hook")
                                .font(.grotesk(12.5))
                                .foregroundStyle(Color.muted)
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.paper)
                .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: 1))
                .padding(.top, 20)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
    }

    private func factRow(_ key: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(key).font(.grotesk(14)).foregroundStyle(Color.muted)
                Spacer()
                Text(value).font(.grotesk(14, .medium)).foregroundStyle(Color.ink)
            }
            .padding(.vertical, 12)
            Hairline()
        }
    }

    private var termsPanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                MonoLabel(text: "Terms of the contract", size: 9.5, tracking: 0.2)
                ForEach(Array(state.rules.enumerated()), id: \.offset) { index, rule in
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(.mono(10))
                                .foregroundStyle(Color.olive)
                                .padding(.top, 3)
                            Text(rule)
                                .font(.grotesk(14.5))
                                .foregroundStyle(Color.bodyText)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 13)
                        Hairline()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Paid on verified views only.")
                        .font(.marker(14))
                        .foregroundStyle(Color.olive)
                    Text("Views are counted 14 days from post. The purse can't run dry mid-window — it's funded up front.")
                        .font(.grotesk(13))
                        .foregroundStyle(Color.bodyText)
                        .lineSpacing(3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.paper)
                .overlay(Rectangle().strokeBorder(Color.strongBorder, lineWidth: 1))
                .padding(.top, 18)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
    }

    private var capturedPanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                MonoLabel(text: "Captured on this sound", size: 9.5, tracking: 0.2)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(state.captured) { clip in
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack(alignment: .bottomLeading) {
                                Rectangle().fill(Color.ink).aspectRatio(9 / 16, contentMode: .fit)
                                Text(clip.serial)
                                    .font(.mono(9))
                                    .tracking(1.25)
                                    .foregroundStyle(Color.paper.opacity(0.6))
                                    .padding(10)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("@\(clip.handle)")
                                    .font(.grotesk(13, .semibold))
                                    .foregroundStyle(Color.ink)
                                HStack {
                                    Text(clip.views).foregroundStyle(Color.muted)
                                    Spacer()
                                    Text(clip.paid).foregroundStyle(Color.olive)
                                }
                                .font(.mono(10))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                        }
                        .background(Color.paper)
                        .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            StampButton(title: "Seize it · \(state.current?.rate ?? "")", fontSize: 13.5) {
                state.seize()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .background(Color.paper)
    }
}

struct BackLink: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("← \(label)".uppercased())
                .font(.mono(10))
                .tracking(1.8)
                .foregroundStyle(Color.muted)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
