import PhotosUI
import SwiftUI

// Screen 6 — numbered sections: camera-roll drop zone / TikTok link,
// automatic checks list, payout preview. Lodge the submission.
// The drop zone becomes a real picker once TikTok's content-posting audit
// unlocks direct posting; until then it's the design's inert affordance and
// the pasted link is the path.
struct SubmitView: View {
    @EnvironmentObject var state: AppState
    @State private var pickedVideo: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: "claims") { state.screen = .claims }
                Text("Submit the clip")
                    .font(.fredericka(28))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 2)
                Text("\(state.current?.serial ?? "") · \(state.current?.title ?? "")")
                    .font(.grotesk(13))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .background(Color.paper)
            .overlay(alignment: .bottom) { Hairline() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    MonoLabel(text: "1 · The post", size: 9.5, tracking: 0.2)
                    if state.canPostFromApp {
                        PhotosPicker(selection: $pickedVideo, matching: .videos) {
                            dropZone
                        }
                        .buttonStyle(.plain)
                        .disabled(state.isPosting)
                        .padding(.top, 10)
                        .onChange(of: pickedVideo) { _, item in
                            guard let item else { return }
                            Task {
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    state.postDirectly(video: data, caption: state.current?.title ?? "")
                                }
                            }
                        }
                    } else {
                        dropZone.padding(.top, 10)
                    }
                    Text("https://tiktok.com/@merrow/video/74…")
                        .font(.mono(12.5))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.paper)
                        .overlay(Rectangle().strokeBorder(Color.strongBorder, lineWidth: 1))
                        .padding(.top, 10)

                    MonoLabel(text: "2 · Automatic checks", size: 9.5, tracking: 0.2)
                        .padding(.top, 22)
                    ForEach(state.submissionChecks) { check in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Text(check.title)
                                    .font(.grotesk(14.5))
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Text(check.state.uppercased())
                                    .font(.mono(9.5))
                                    .tracking(1.33)
                                    .foregroundStyle(check.passed == nil ? Color.muted : Color.olive)
                            }
                            .padding(.vertical, 13)
                            Hairline()
                        }
                    }

                    MonoLabel(text: "3 · What you'll be paid", size: 9.5, tracking: 0.2)
                        .padding(.top, 22)
                    payoutPreview.padding(.top, 10)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }

            VStack(spacing: 0) {
                Hairline()
                StampButton(title: "Lodge the submission", fontSize: 13.5) { state.finishSubmit() }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }
            .background(Color.paper)
        }
        .background(Color.card)
    }

    private var dropZone: some View {
        VStack(spacing: 0) {
            Text("MP4")
                .font(.mono(9))
                .tracking(0.9)
                .foregroundStyle(Color.paper)
                .frame(width: 56, height: 56)
                .background(Color.ink)
            Text("Pick from camera roll")
                .font(.grotesk(14.5, .medium))
                .foregroundStyle(Color.ink)
                .padding(.top, 12)
            Text("or paste the TikTok link below")
                .font(.grotesk(12.5))
                .foregroundStyle(Color.muted)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color.paper)
        .overlay(
            Rectangle()
                .strokeBorder(Color.strongBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private var payoutPreview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("rate").foregroundStyle(Color.bodyText)
                Spacer()
                Text(state.current?.rate ?? "").foregroundStyle(Color.bodyText)
            }
            .font(.grotesk(14))
            HStack {
                Text("counting window").foregroundStyle(Color.bodyText)
                Spacer()
                Text("14 days from post").foregroundStyle(Color.bodyText)
            }
            .font(.grotesk(14))
            .padding(.top, 8)

            Hairline().padding(.top, 14)
            HStack(alignment: .firstTextBaseline) {
                Text("purse remaining")
                    .font(.grotesk(14))
                    .foregroundStyle(Color.bodyText)
                Spacer()
                Text(state.current?.purse ?? "")
                    .font(.fredericka(24))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(Color.paper)
        .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: 1))
    }
}
