import SwiftUI

// The Stage — skin on top, bounty clip feed underneath, one draggable split.
//
// Both panes are live at once and neither rebuilds the other: scrolling the
// feed doesn't reset the skin's state, and switching skins doesn't reset the
// feed cursor. That property is the whole product, so be careful with view
// identity if this file grows.
struct StageView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var stage: StageModel

    @State private var showSwitcher = false
    @State private var dragStartRatio: Double?

    private let dividerHeight: CGFloat = 18

    @MainActor
    init(bounty: Bounty?, api: BountyAPI, attention: AttentionRecorder) {
        _stage = StateObject(wrappedValue: StageModel(bounty: bounty, api: api, attention: attention))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            GeometryReader { geo in panes(in: geo.size.height) }
        }
        .background(Color.paper)
        .environmentObject(stage)
        .task { await stage.load() }
        .onDisappear { stage.close() }
        .sheet(isPresented: $showSwitcher) {
            SkinSwitcher(current: stage.skinID) { picked in
                stage.skinID = picked
                showSwitcher = false
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { state.screen = .board } label: {
                MonoLabel(text: "← Board", size: 10, tracking: 0.16, color: .muted)
            }
            .buttonStyle(.plain)

            Text(stage.bounty?.song ?? "The Stage")
                .font(.serif(15, .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            Spacer()

            Button { showSwitcher = true } label: {
                MonoLabel(text: "Skins", size: 10, tracking: 0.16, color: .crimson, bold: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func panes(in height: CGFloat) -> some View {
        let usable = max(height - dividerHeight, 1)
        let skinHeight = stage.skinID == SkinCatalog.none.id ? 0 : usable * CGFloat(stage.splitRatio)

        VStack(spacing: 0) {
            if skinHeight > 0 {
                SkinCatalog.view(for: stage.skinID)
                    .frame(height: skinHeight)
                    .clipped()
                divider(usable: usable)
            }
            ClipFeedView()
                .frame(maxHeight: .infinity)
        }
    }

    // Grab handle. Ratio is committed on drag end rather than per frame — a
    // single adjustment would otherwise emit hundreds of split_change events.
    private func divider(usable: CGFloat) -> some View {
        ZStack {
            Color.paper
            Rectangle()
                .fill(Color.strongBorder)
                .frame(width: 44, height: 2)
        }
        .frame(height: dividerHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = dragStartRatio ?? stage.splitRatio
                    dragStartRatio = start
                    stage.setRatio(start + Double(value.translation.height / usable))
                }
                .onEnded { _ in
                    dragStartRatio = nil
                    stage.commitRatio()
                }
        )
    }
}

// MARK: - Switcher

private struct SkinSwitcher: View {
    @EnvironmentObject var entitlements: EntitlementStore
    let current: String
    let pick: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Skins")
                    .font(.fredericka(26))
                    .foregroundStyle(Color.ink)
                Spacer()
                Button { Task { await entitlements.restore() } } label: {
                    MonoLabel(text: "Restore", size: 9, tracking: 0.16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Hairline()

            ScrollView {
                VStack(spacing: 0) {
                    row(for: SkinCatalog.none)
                    ForEach(SkinCatalog.all) { row(for: $0) }
                }
            }
        }
        .background(Color.paper)
    }

    private func row(for skin: SkinDescriptor) -> some View {
        SkinRow(
            skin: skin,
            isCurrent: skin.id == current,
            owned: entitlements.owns(skin),
            price: entitlements.priceLabel(for: skin),
            busy: skin.productID != nil && entitlements.purchasing == skin.productID
        ) {
            if entitlements.owns(skin) {
                pick(skin.id)
            } else {
                Task { if await entitlements.purchase(skin) { pick(skin.id) } }
            }
        }
    }
}

private struct SkinRow: View {
    let skin: SkinDescriptor
    let isCurrent: Bool
    let owned: Bool
    let price: String
    let busy: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(alignment: .center, spacing: 14) {
                glyph
                copy
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(minHeight: 64)
            .background(isCurrent ? Color.card : .clear)
            .overlay(alignment: .bottom) { Hairline() }
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var glyph: some View {
        Text(skin.glyph)
            .font(.mono(15, bold: true))
            .foregroundStyle(Color.ink)
            .frame(width: 28, height: 28)
            .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: 1))
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(skin.name)
                .font(.serif(15, .semibold))
                .foregroundStyle(Color.ink)
            Text(skin.tagline)
                .font(.grotesk(13))
                .foregroundStyle(Color.muted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if busy {
            MonoLabel(text: "…", size: 11, tracking: 0.1)
        } else if isCurrent {
            MonoLabel(text: "On", size: 9, tracking: 0.18, color: .olive, bold: true)
        } else if owned {
            MonoLabel(text: "Use", size: 9, tracking: 0.18, color: .ink)
        } else {
            MonoLabel(text: price, size: 10, tracking: 0.14, color: .crimson, bold: true)
        }
    }
}
