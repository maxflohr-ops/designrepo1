import SwiftUI

// Screen 5 — reason-given callout (crimson tint), case statement, evidence
// rows, amount-held box, 72-hour SLA note, Send the appeal.
struct AppealView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: "claims") { state.screen = .claims }
                MonoLabel(text: "Held for review", size: 10, tracking: 0.2, color: .crimson)
                    .padding(.top, 4)
                Text("File an appeal")
                    .font(.fredericka(28))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .background(Color.paper)
            .overlay(alignment: .bottom) { Hairline() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel(text: "Reason given", size: 9.5, tracking: 0.18, color: .crimson, bold: true)
                        Text("Sound did not match the contract audio. Counted views held at 88,000 pending resolution.")
                            .font(.grotesk(14.5))
                            .foregroundStyle(Color.bodyText)
                            .lineSpacing(4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.crimson.opacity(0.06))
                    .overlay(Rectangle().strokeBorder(Color.crimson, lineWidth: 1))

                    MonoLabel(text: "Your case", size: 9.5, tracking: 0.2)
                        .padding(.top, 20)
                    Text("The sound page shows the licensed upload — TikTok relinked it after the artist renamed the track on Aug 03.")
                        .font(.grotesk(14.5))
                        .foregroundStyle(Color.bodyText)
                        .lineSpacing(4)
                        .padding(13)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .background(Color.paper)
                        .overlay(Rectangle().strokeBorder(Color.strongBorder, lineWidth: 1))
                        .padding(.top, 9)

                    MonoLabel(text: "Evidence attached", size: 9.5, tracking: 0.2)
                        .padding(.top, 20)
                    ForEach(state.evidence) { row in
                        VStack(spacing: 0) {
                            HStack {
                                Text(row.title)
                                    .font(.grotesk(14.5))
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Text(row.value.uppercased())
                                    .font(.mono(9.5))
                                    .tracking(1.33)
                                    .foregroundStyle(Color.olive)
                            }
                            .padding(.vertical, 13)
                            Hairline()
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("amount held")
                                .font(.grotesk(14))
                                .foregroundStyle(Color.bodyText)
                            Spacer()
                            Text("$88")
                                .font(.fredericka(24))
                                .foregroundStyle(Color.ink)
                        }
                        Text("Appeals are answered inside 72 hours. The purse stays reserved until then.")
                            .font(.grotesk(12.5))
                            .foregroundStyle(Color.muted)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color.paper)
                    .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: 1))
                    .padding(.top, 20)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }

            VStack(spacing: 0) {
                Hairline()
                StampButton(title: "Send the appeal", fontSize: 13.5) { state.sendAppeal() }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }
            .background(Color.paper)
        }
        .background(Color.card)
    }
}
