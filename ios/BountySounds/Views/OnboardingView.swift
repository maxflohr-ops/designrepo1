import SwiftUI

// Screen 1 — seal, triple-bordered plaque, two CTAs.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Image("GreatSeal")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .padding(.top, 48)
                .accessibilityHidden(true)

            // triple border: hairline → strong → 2px ink
            plaque
                .padding(13)
                .overlay(Rectangle().strokeBorder(Color.strongBorder, lineWidth: 1).padding(11))
                .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: 1))
                .padding(.top, 24)

            Spacer()

            VStack(spacing: 10) {
                StampButton(title: state.isAuthenticating ? "Opening TikTok…" : "Continue with TikTok") {
                    state.enterClipper()
                }
                StampButton(title: "I'm posting a bounty", fill: .clear, textColor: .ink, border: .ink) {
                    state.enterArtist()
                }
                Text("no invites · no gated discord")
                    .font(.marker(13))
                    .foregroundStyle(Color.olive)
                    .padding(.top, 4)
            }
            .disabled(state.isAuthenticating)
            .opacity(state.isAuthenticating ? 0.6 : 1)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }

    private var plaque: some View {
        ZStack {
            Image("GuillocheRosette")
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .opacity(0.05)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                MonoLabel(text: "— Bounty Board —", size: 10, tracking: 0.22)
                (Text("Clip it.\n") + Text("Claim it.\n").italic() + Text("Cash it."))
                    .font(.fredericka(46))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(0)
                    .padding(.top, 16)
                Text("The purse is posted before you cut. Verified views pay out.")
                    .font(.grotesk(14.5))
                    .foregroundStyle(Color.bodyText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 250)
                    .padding(.top, 18)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .background(Color.card)
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
        .clipped()
    }
}
