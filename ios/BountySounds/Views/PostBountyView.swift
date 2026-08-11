import SwiftUI

// Screen 11 — Artist: sound card, brief, Per-views|Per-clip payout toggle,
// purse presets, live purse math line, live contract preview, crimson Fund
// the purse CTA.
struct PostBountyView: View {
    @EnvironmentObject var state: AppState
    private let presets = [250, 500, 1000, 2500]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: "Artist mode", size: 10, tracking: 0.2, color: .crimson)
                Text("Post a bounty")
                    .font(.fredericka(28))
                    .foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background(Color.paper)
            .overlay(alignment: .bottom) { Hairline() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    MonoLabel(text: "The sound", size: 9.5, tracking: 0.2)
                    soundCard.padding(.top, 9)

                    MonoLabel(text: "The brief", size: 9.5, tracking: 0.2)
                        .padding(.top, 20)
                    Text("Best 20 seconds of the Thursday broadcast. Sound must be the listed audio, no re-uploads.")
                        .font(.grotesk(14.5))
                        .foregroundStyle(Color.bodyText)
                        .lineSpacing(4)
                        .padding(13)
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                        .background(Color.paper)
                        .overlay(Rectangle().strokeBorder(Color.strongBorder, lineWidth: 1))
                        .padding(.top, 9)

                    MonoLabel(text: "How it pays", size: 9.5, tracking: 0.2)
                        .padding(.top, 20)
                    payoutToggle.padding(.top, 9)

                    HStack(alignment: .top, spacing: 12) {
                        valueBox(label: "Rate", value: state.payoutModel.rateLabel)
                        valueBox(label: "Purse", value: state.purseLabel)
                    }
                    .padding(.top, 14)

                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { amount in
                            presetButton(amount)
                        }
                    }
                    .padding(.top, 10)

                    Text(state.purseMath)
                        .font(.grotesk(12.5))
                        .foregroundStyle(Color.muted)
                        .padding(.top, 12)

                    contractPreview
                        .padding(12)
                        .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: 1))
                        .padding(.top, 20)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }

            VStack(spacing: 0) {
                Hairline()
                StampButton(title: "Fund the purse · \(state.purseLabel)",
                            fill: .crimson, textColor: .white, fontSize: 13.5) {
                    state.fundPurse()
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            .background(Color.paper)
        }
        .background(Color.card)
    }

    private var soundCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("ART")
                    .font(.mono(9))
                    .foregroundStyle(Color.paper)
                    .frame(width: 46, height: 46)
                    .background(Color.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.soundLink.isEmpty ? "Northsider — Ridge Club" : "Sound linked")
                        .font(.grotesk(15, .semibold))
                        .foregroundStyle(Color.ink)
                    Text(state.soundLink.isEmpty ? "linked from TikTok sound page" : "resolved when the purse is funded")
                        .font(.grotesk(12.5))
                        .foregroundStyle(Color.muted)
                }
                Spacer()
            }
            .padding(12)
            TextField("or paste the TikTok sound link", text: $state.soundLink)
                .font(.mono(12.5))
                .foregroundStyle(Color.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .overlay(alignment: .top) { Hairline() }
                .accessibilityLabel("TikTok sound link")
        }
        .background(Color.paper)
        .overlay(Rectangle().strokeBorder(Color.strongBorder, lineWidth: 1))
    }

    private var payoutToggle: some View {
        HStack(spacing: 0) {
            ForEach(PayoutModel.allCases, id: \.rawValue) { model in
                Button {
                    state.payoutModel = model
                } label: {
                    Text(model.label.uppercased())
                        .font(.grotesk(12, .semibold))
                        .tracking(0.72)
                        .foregroundStyle(state.payoutModel == model ? Color.paper : Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(state.payoutModel == model ? Color.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1))
    }

    private func valueBox(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MonoLabel(text: label, size: 9.5, tracking: 0.16)
            Text(value)
                .font(.fredericka(19))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.paper)
                .overlay(Rectangle().strokeBorder(Color.strongBorder, lineWidth: 1))
        }
    }

    private func presetButton(_ amount: Int) -> some View {
        let active = state.purseSelection == amount
        return Button {
            state.purseSelection = amount
        } label: {
            Text("$\(amount.formatted())")
                .font(.mono(11))
                .tracking(0.66)
                .foregroundStyle(active ? Color.paper : Color.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(active ? Color.ink : Color.clear)
                .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var contractPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoLabel(text: "Preview", size: 9, tracking: 0.2, color: .crimson, bold: true)
                Spacer()
                Text("B 00000148")
                    .font(.mono(9))
                    .tracking(1.35)
                    .foregroundStyle(Color.olive)
            }
            .padding(.bottom, 7)
            Hairline()

            Text(state.purseLabel)
                .font(.fredericka(34))
                .foregroundStyle(Color.ink)
                .padding(.top, 10)
            Text("Clip the Thursday stream")
                .font(.fredericka(22))
                .foregroundStyle(Color.ink)
                .padding(.top, 10)
            Text("for “Northsider — Ridge Club”")
                .font(.grotesk(13))
                .italic()
                .foregroundStyle(Color.bodyText)
                .padding(.top, 4)
            Text(state.payoutModel.rateLabel)
                .font(.fredericka(17))
                .foregroundStyle(Color.ink)
                .padding(.top, 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.paper)
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
    }
}
