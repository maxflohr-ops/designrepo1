import SwiftUI

// Screen 10 — ranked list, "you" row tinted olive; top-20 early-access note.
struct RosterView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: "desk") { state.screen = .me }
                Text("The roster")
                    .font(.fredericka(30))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 2)
                Text("Points are paid views, all bounties, rolling 90 days.")
                    .font(.grotesk(13))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) { Hairline() }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(state.roster.enumerated()), id: \.element.id) { index, row in
                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                Text(row.rank)
                                    .font(.mono(11))
                                    .tracking(0.66)
                                    .foregroundStyle(Color.muted)
                                    .frame(width: 28, alignment: .leading)
                                Text(row.initials)
                                    .font(.mono(9))
                                    .foregroundStyle(Color.paper)
                                    .frame(width: 34, height: 34)
                                    .background(Color.ink)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("@\(row.handle)")
                                        .font(.grotesk(14.5, .medium))
                                        .foregroundStyle(Color.ink)
                                    Text(row.meta)
                                        .font(.mono(10))
                                        .tracking(1)
                                        .foregroundStyle(Color.muted)
                                }
                                Spacer()
                                Text(row.points)
                                    .font(.fredericka(18))
                                    .foregroundStyle(Color.ink)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 13)
                            .background(rowBackground(row, index: index))
                            Hairline()
                        }
                    }
                    Text("Top twenty get first look at new purses for 24 hours before the board opens.")
                        .font(.grotesk(12.5))
                        .foregroundStyle(Color.muted)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                }
            }
        }
    }

    private func rowBackground(_ row: RosterRow, index: Int) -> Color {
        if row.isYou { return Color.olive.opacity(0.12) }
        return index.isMultiple(of: 2) ? Color.card : Color.paper
    }
}
