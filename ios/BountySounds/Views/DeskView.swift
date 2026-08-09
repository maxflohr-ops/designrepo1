import SwiftUI

// Screen 9 — avatar, handle, points/rank; Clipper|Artist segmented mode
// switch (swaps the whole tab bar); settings rows; roster row → Roster;
// cardinal art footer.
struct DeskView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("MW")
                    .font(.mono(11))
                    .foregroundStyle(Color.paper)
                    .frame(width: 54, height: 54)
                    .background(Color.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("@merrowcuts")
                        .font(.serif(20, .bold))
                        .foregroundStyle(Color.ink)
                    MonoLabel(text: "1,240 pts · rank 014", size: 10, tracking: 0.14, color: .olive)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .overlay(alignment: .bottom) { Hairline() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    MonoLabel(text: "Mode", size: 9.5, tracking: 0.2)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)

                    modeSwitch
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    Text("Artist mode swaps the whole app: post bounties, fund purses, review submissions.")
                        .font(.grotesk(12.5))
                        .foregroundStyle(Color.muted)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        ForEach(state.settings) { row in
                            settingRow(row)
                        }
                    }
                    .padding(.top, 18)

                    Image("Cardinal")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104)
                        .opacity(0.55)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 26)
                        .padding(.bottom, 20)
                }
            }
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            modeButton("Clipper", isActive: state.mode == .clipper) { state.setMode(.clipper) }
            Rectangle().fill(Color.ink).frame(width: 1)
            modeButton("Artist", isActive: state.mode == .artist) { state.setMode(.artist) }
        }
        .frame(height: 46)
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func modeButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.grotesk(12.5, .semibold))
                .tracking(1)
                .foregroundStyle(isActive ? Color.paper : Color.ink)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(isActive ? Color.ink : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingRow(_ row: SettingRow) -> some View {
        Button {
            if row.title == "The roster" { state.screen = .roster }
        } label: {
            VStack(spacing: 0) {
                HStack {
                    Text(row.title)
                        .font(.grotesk(15))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Text(row.value)
                        .font(.mono(11))
                        .foregroundStyle(Color.muted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .frame(minHeight: 44)
                Hairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
