import SwiftUI

// Screen 4 — claimed card with the 4-item checklist (tap to toggle,
// ink-filled checkbox, strikethrough), countdown, olive Submit CTA, and the
// under-review rows. The disputed row opens the appeal.
struct ClaimsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel(text: "Your desk", size: 10, tracking: 0.2)
                Text("Claims in hand")
                    .font(.fredericka(30))
                    .foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) { Hairline() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    claimedCard
                    MonoLabel(text: "Under review", size: 9.5, tracking: 0.2)
                        .padding(.top, 20)
                    ForEach(state.reviewing) { claim in
                        reviewRow(claim)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private var claimedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoLabel(text: "Claimed", size: 9, tracking: 0.2, color: .crimson, bold: true)
                Spacer()
                Text(state.current?.serial ?? "")
                    .font(.mono(9))
                    .tracking(1.35)
                    .foregroundStyle(Color.olive)
            }
            .padding(.bottom, 8)
            Hairline()

            Text(state.current?.title ?? "")
                .font(.fredericka(22))
                .foregroundStyle(Color.ink)
                .padding(.top, 12)
            HStack {
                Text(state.current?.rate ?? "")
                Spacer()
                Text("6 days left to post")
            }
            .font(.grotesk(12.5))
            .foregroundStyle(Color.muted)
            .padding(.top, 8)

            Hairline().padding(.top, 16)
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(text: "Checklist", size: 9.5, tracking: 0.2)
                Spacer()
                Text(state.checkProgress)
                    .font(.mono(9.5))
                    .foregroundStyle(Color.olive)
            }
            .padding(.top, 12)

            ForEach(state.steps) { step in
                checklistRow(step)
            }

            StampButton(title: "Submit the clip", fill: .olive, minHeight: 48) {
                state.screen = .submit
            }
            .padding(.top, 16)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(Color.card)
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
    }

    private func checklistRow(_ step: ChecklistStep) -> some View {
        let done = state.checklistDone.indices.contains(step.id) && state.checklistDone[step.id]
        return Button {
            state.toggleStep(step.id)
        } label: {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Text(done ? "✓" : "")
                        .font(.grotesk(12))
                        .foregroundStyle(Color.paper)
                        .frame(width: 19, height: 19)
                        .background(done ? Color.ink : Color.clear)
                        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.grotesk(14.5))
                            .foregroundStyle(Color.ink)
                            .strikethrough(done)
                        Text(step.subtitle)
                            .font(.grotesk(12.5))
                            .foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                Hairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reviewRow(_ claim: ReviewingClaim) -> some View {
        let disputed = claim.state == "disputed"
        return Button {
            if disputed { state.screen = .dispute }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(claim.title)
                        .font(.serif(15.5, .bold))
                        .foregroundStyle(Color.ink)
                    Text(claim.meta)
                        .font(.grotesk(12.5))
                        .foregroundStyle(Color.muted)
                }
                Spacer()
                Text(claim.state.uppercased())
                    .font(.mono(9))
                    .tracking(1.26)
                    .foregroundStyle(disputed ? Color.crimson : Color.olive)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(Rectangle().strokeBorder(disputed ? Color.crimson : Color.olive, lineWidth: 1))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background(Color.card)
            .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
