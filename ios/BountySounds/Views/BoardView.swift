import SwiftUI

// Screen 2 — full-screen contract cards, vertical scroll-snap, one per
// viewport, with the share-sheet banner when deep-linked from TikTok.
struct BoardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bounty Sounds")
                    .font(.serif(19, .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
                MonoLabel(text: "\(state.bounties.count) open", size: 10, tracking: 0.16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if state.showShareBanner {
                shareBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if state.bounties.isEmpty {
                emptyBoard
            } else {
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(state.bounties.enumerated()), id: \.element.id) { index, bounty in
                                ContractCard(bounty: bounty) { state.openBounty(index) }
                                    .padding(.bottom, 10)
                                    .frame(height: geo.size.height)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var emptyBoard: some View {
        VStack(spacing: 0) {
            Spacer()
            MonoLabel(text: "— Bounty Board —", size: 10, tracking: 0.22)
            Text("The board is quiet.")
                .font(.fredericka(30))
                .foregroundStyle(Color.ink)
                .padding(.top, 14)
            Text("New purses hit the wire the moment they're funded. Turn on push and you'll hear first.")
                .font(.grotesk(14.5))
                .foregroundStyle(Color.bodyText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 260)
                .padding(.top, 12)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private var shareBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            MonoLabel(text: "Shared", size: 9, tracking: 0.18, color: .olive, bold: true)
            Text("Two live bounties on the sound you sent over from TikTok.")
                .font(.grotesk(13))
                .foregroundStyle(Color.bodyText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                state.showShareBanner = false
            } label: {
                Text("✕")
                    .font(.grotesk(15))
                    .foregroundStyle(Color.muted)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 13)
        .background(Color.olive.opacity(0.1))
        .overlay(Rectangle().strokeBorder(Color.olive, lineWidth: 1))
    }
}

struct ContractCard: View {
    let bounty: Bounty
    let open: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("GuillocheRosette")
                .resizable()
                .scaledToFit()
                .frame(width: 280)
                .opacity(0.06)
                .offset(x: 130, y: 130)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MonoLabel(text: "Contract", size: 9, tracking: 0.22, color: .crimson, bold: true)
                    Spacer()
                    Text(bounty.serial)
                        .font(.mono(9))
                        .tracking(1.35)
                        .foregroundStyle(Color.olive)
                }
                .padding(.bottom, 8)
                Hairline()

                MonoLabel(text: "Purse posted", size: 10, tracking: 0.2)
                    .padding(.top, 20)
                Text(bounty.purse)
                    .font(.fredericka(54))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 2)

                Text(bounty.title)
                    .font(.fredericka(27))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(2)
                    .padding(.top, 22)
                Text("for “\(bounty.song)”")
                    .font(.grotesk(15))
                    .italic()
                    .foregroundStyle(Color.bodyText)
                    .padding(.top, 8)
                Text(bounty.brief)
                    .font(.grotesk(14.5))
                    .foregroundStyle(Color.bodyText)
                    .lineSpacing(4)
                    .padding(.top, 14)

                Spacer(minLength: 12)

                Hairline()
                MonoLabel(text: "Reward", size: 10, tracking: 0.2)
                    .padding(.top, 13)
                Text(bounty.rate)
                    .font(.fredericka(21))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 4)
                HStack(spacing: 16) {
                    Text(bounty.platform)
                    Text("by \(bounty.deadline)")
                    Text(bounty.slots)
                }
                .font(.grotesk(12))
                .foregroundStyle(Color.muted)
                .padding(.top, 8)

                StampButton(title: "Open contract", minHeight: 48, action: open)
                    .padding(.top, 14)

                MonoLabel(text: "swipe up · next contract", size: 9, tracking: 0.18)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 11)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.card)
        .clipped()
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}
