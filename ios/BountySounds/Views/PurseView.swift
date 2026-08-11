import SwiftUI

// Screen 7 — payable amount display, pending/lifetime, Cash out (Face ID),
// ledger rows (+olive / −ink / held crimson), payout method card.
struct PurseView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                MonoLabel(text: "Cleared and payable", size: 10, tracking: 0.2)
                Text(state.purseAmounts.payable)
                    .font(.fredericka(60))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 8)
                HStack(spacing: 20) {
                    Text(state.purseAmounts.pending)
                    Text(state.purseAmounts.lifetime)
                }
                .font(.grotesk(13))
                .foregroundStyle(Color.muted)
                .padding(.top, 12)

                StampButton(title: "Cash out · Face ID", minHeight: 48) {
                    state.flash("Cash out sent. Face ID confirmed.")
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    MonoLabel(text: "Ledger", size: 9.5, tracking: 0.2)
                        .padding(.horizontal, 4)
                    ForEach(state.ledger) { row in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.title)
                                        .font(.grotesk(14.5, .medium))
                                        .foregroundStyle(Color.ink)
                                    Text(row.meta)
                                        .font(.mono(10))
                                        .tracking(1)
                                        .foregroundStyle(Color.muted)
                                }
                                Spacer()
                                Text(row.amount)
                                    .font(.fredericka(19))
                                    .foregroundStyle(toneColor(row.tone))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 14)
                            Hairline()
                        }
                    }

                    payoutMethod.padding(.top, 18)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func toneColor(_ tone: LedgerRow.Tone) -> Color {
        switch tone {
        case .credit: .olive
        case .debit: .ink
        case .held: .crimson
        }
    }

    private var payoutMethod: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(text: "Payout method", size: 9.5, tracking: 0.2)
            HStack {
                Text("PayPal · m•••@mail.com")
                    .font(.grotesk(14.5))
                    .foregroundStyle(Color.ink)
                Spacer()
                Button {
                    state.openPayoutOnboarding()
                } label: {
                    Text("change")
                        .font(.mono(10))
                        .foregroundStyle(Color.olive)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
            Text("Stripe and USDC also available. Face ID confirms every cash-out.")
                .font(.grotesk(12.5))
                .foregroundStyle(Color.muted)
                .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: 1))
    }
}
