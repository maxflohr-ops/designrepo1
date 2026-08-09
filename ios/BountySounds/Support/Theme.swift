import SwiftUI

// Design tokens from the handoff README — mirrors the web app's system.
// Square corners everywhere; no border-radius in this app.
extension Color {
    static let ink = Color(hex: 0x0D0D0D)          // primary text, borders, filled buttons
    static let paper = Color(hex: 0xF5F3EE)        // app background
    static let card = Color(hex: 0xFAF9F5)         // card/sheet surfaces
    static let bodyText = Color(hex: 0x2D2D2D)     // body text
    static let muted = Color(hex: 0x6B6B6B)        // secondary text, labels
    static let olive = Color(hex: 0x6F7F5C)        // success, money-positive, secondary CTA
    static let crimson = Color(hex: 0x9E3B2F)      // Contract stamps, artist mode, warnings
    static let hairline = Color.ink.opacity(0.15)
    static let strongBorder = Color.ink.opacity(0.35)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// Typography: Fredericka the Great (display), Source Serif 4 (wordmark/card
// titles), Space Grotesk (UI body, buttons), Space Mono (labels, serials, tab
// bar), Permanent Marker (rare marginalia).
extension Font {
    static func fredericka(_ size: CGFloat) -> Font { .custom("FrederickatheGreat-Regular", size: size) }
    static func marker(_ size: CGFloat) -> Font { .custom("PermanentMarker-Regular", size: size) }

    static func serif(_ size: CGFloat, _ weight: SerifWeight = .semibold) -> Font {
        .custom(weight.postScript, size: size)
    }
    enum SerifWeight { case regular, semibold, bold
        var postScript: String {
            switch self {
            case .regular: "SourceSerif4-Regular"
            case .semibold: "SourceSerif4-SemiBold"
            case .bold: "SourceSerif4-Bold"
            }
        }
    }

    static func grotesk(_ size: CGFloat, _ weight: GroteskWeight = .regular) -> Font {
        .custom(weight.postScript, size: size)
    }
    enum GroteskWeight { case regular, medium, semibold, bold
        var postScript: String {
            switch self {
            case .regular: "SpaceGrotesk-Regular"
            case .medium: "SpaceGrotesk-Medium"
            case .semibold: "SpaceGrotesk-SemiBold"
            case .bold: "SpaceGrotesk-Bold"
            }
        }
    }

    static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size)
    }
}

// Space Mono micro-labels: uppercase, letter-spacing .1–.22em at 9–11px.
struct MonoLabel: View {
    let text: String
    var size: CGFloat = 10
    var tracking: CGFloat = 0.2  // em
    var color: Color = .muted
    var bold = false

    var body: some View {
        Text(text.uppercased())
            .font(.mono(size, bold: bold))
            .tracking(size * tracking)
            .foregroundStyle(color)
    }
}

// Filled/outline CTA — square, uppercase Space Grotesk, ≥44pt hit target.
struct StampButton: View {
    let title: String
    var fill: Color = .ink
    var textColor: Color = .paper
    var border: Color? = nil
    var minHeight: CGFloat = 52
    var fontSize: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.grotesk(fontSize, .semibold))
                .tracking(fontSize * 0.09)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .background(fill)
        .overlay(Rectangle().strokeBorder(border ?? (fill == .clear ? .ink : fill), lineWidth: 1))
        .buttonStyle(.plain)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Color.hairline).frame(height: 1) }
}
