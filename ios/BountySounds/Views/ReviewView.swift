import SwiftUI

// Screen 12 — Artist: thumbnail rows with Approve (olive, pays) / Dispute
// (holds, 72h appeal), settled states, purse-remaining card with Top up.
struct ReviewView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel(text: "Artist mode", size: 10, tracking: 0.2, color: .crimson)
                Text("Submissions")
                    .font(.fredericka(30))
                    .foregroundStyle(Color.ink)
                Text("\(state.pendingReviewCount) waiting · \(state.purseLabel) purse, \(state.unspentLabel) unspent")
                    .font(.grotesk(13))
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) { Hairline() }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(state.artistSubmissions) { submission in
                        submissionRow(submission)
                    }
                    purseRemaining
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
    }

    private func submissionRow(_ submission: ArtistSubmission) -> some View {
        let verdict = state.verdicts[submission.id]
        return HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color.ink).frame(width: 74, height: 112)
                Text(submission.serial)
                    .font(.mono(8))
                    .tracking(0.96)
                    .foregroundStyle(Color.paper.opacity(0.55))
                    .padding(7)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("@\(submission.handle)")
                    .font(.grotesk(15, .semibold))
                    .foregroundStyle(Color.ink)
                Text(submission.meta.uppercased())
                    .font(.mono(10))
                    .tracking(1)
                    .foregroundStyle(Color.muted)
                    .padding(.top, 4)
                Text("owed \(state.dollars(submission.owedCents))")
                    .font(.grotesk(13))
                    .foregroundStyle(Color.bodyText)
                    .padding(.top, 6)

                Spacer(minLength: 10)

                if let verdict {
                    Text(verdict == .approved ? "APPROVED · PAID" : "DISPUTED · HELD")
                        .font(.mono(10))
                        .tracking(1.6)
                        .foregroundStyle(verdict == .approved ? Color.olive : Color.crimson)
                } else {
                    HStack(spacing: 8) {
                        Button {
                            state.approve(submission)
                        } label: {
                            Text("APPROVE")
                                .font(.grotesk(11.5, .semibold))
                                .tracking(0.92)
                                .foregroundStyle(Color.paper)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.olive)
                                .overlay(Rectangle().strokeBorder(Color.olive, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Button {
                            state.dispute(submission)
                        } label: {
                            Text("DISPUTE")
                                .font(.grotesk(11.5, .semibold))
                                .tracking(0.92)
                                .foregroundStyle(Color.bodyText)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .overlay(Rectangle().strokeBorder(Color.strongBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 112)
        }
        .padding(12)
        .background(Color.card)
        .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: 1))
    }

    private var purseRemaining: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(text: "Purse remaining", size: 9.5, tracking: 0.2)
                Spacer()
                Text(state.unspentLabel)
                    .font(.fredericka(24))
                    .foregroundStyle(Color.ink)
            }
            StampButton(title: "Top up · +$250", fill: .clear, textColor: .ink,
                        border: .ink, minHeight: 44, fontSize: 12.5) {
                state.topUp()
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(Color.paper)
        .overlay(Rectangle().strokeBorder(Color.strongBorder, lineWidth: 1))
    }
}
