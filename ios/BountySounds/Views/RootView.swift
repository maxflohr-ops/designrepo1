import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                screenBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if state.showTabs { TabBar() }
            }

            if let toast = state.toast {
                ToastView(message: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, state.showTabs ? 96 : 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.toast)
        .statusBarHidden(false)
    }

    @ViewBuilder private var screenBody: some View {
        switch state.screen {
        case .onboard: OnboardingView()
        case .board: BoardView()
        case .detail: BountyDetailView()
        case .claims: ClaimsView()
        case .dispute: AppealView()
        case .submit: SubmitView()
        case .purse: PurseView()
        case .alerts: WireView()
        case .me: DeskView()
        case .roster: RosterView()
        case .post: PostBountyView()
        case .review: ReviewView()
        case .stage:
            // Keyed on the bounty so the Stage rebuilds if the board loads
            // underneath it (the CI harness opens .stage before load()
            // finishes); the normal entry from the detail screen already
            // has `current` set, so the key never changes there.
            StageView(bounty: state.current, api: state.api, attention: state.attention)
                .id(state.current?.id)
        }
    }
}

// Toasts: ink bar, bottom-anchored above the tab bar, "Sealed" label,
// auto-dismissed by AppState after 2.6s.
struct ToastView: View {
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MonoLabel(text: "Sealed", size: 9, tracking: 0.2, color: .olive)
            Text(message)
                .font(.grotesk(13.5))
                .foregroundStyle(Color.paper)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(Color.ink)
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1))
    }
}

// Text-only tab bar: Space Mono uppercase with a 2px underline on the active
// tab. Every target comfortably clears 44pt.
struct TabBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(state.tabs, id: \.label) { tab in
                    Button {
                        state.screen = tab.screen
                    } label: {
                        VStack(spacing: 3) {
                            Text(tab.label.uppercased())
                                .font(.mono(10))
                                .tracking(1.6)
                                .foregroundStyle(state.screen == tab.screen ? Color.ink : Color.muted)
                            Rectangle()
                                .fill(state.screen == tab.screen ? Color.ink : Color.clear)
                                .frame(width: 34, height: 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)
        }
        .background(Color.paper)
    }
}
