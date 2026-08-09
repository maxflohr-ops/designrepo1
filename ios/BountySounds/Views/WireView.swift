import SwiftUI

// Screen 8 — the wire: unread rows on card background with olive/crimson dots.
struct WireView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("The wire")
                    .font(.fredericka(30))
                    .foregroundStyle(Color.ink)
                Text("Push when a purse lands on a sound you clip.")
                    .font(.grotesk(13))
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) { Hairline() }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(state.wire) { item in
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(dotColor(item.tone))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.body)
                                        .font(.grotesk(14.5))
                                        .foregroundStyle(Color.ink)
                                        .lineSpacing(3)
                                    Text(item.when.uppercased())
                                        .font(.mono(10))
                                        .tracking(1.2)
                                        .foregroundStyle(Color.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 15)
                            .background(item.unread ? Color.card : Color.paper)
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    private func dotColor(_ tone: WireItem.Tone) -> Color {
        switch tone {
        case .money: .olive
        case .warn: .crimson
        case .info: .muted
        }
    }
}
