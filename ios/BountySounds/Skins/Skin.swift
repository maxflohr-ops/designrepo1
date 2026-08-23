import SwiftUI

// A skin is the top half of the Stage: a small, self-contained tool the user
// runs while the clip feed plays underneath. Skins are native SwiftUI compiled
// into the binary — Apple's guideline 4.7 permits HTML5 mini apps but 4.7.2
// forbids bridging native APIs into them without prior approval, and native
// skins avoid that whole surface. See docs/skins/FEASIBILITY.md §1.
//
// The catalog is data (copy, price, order, availability can move server-side);
// the skins themselves are code and need a submission to add.

struct SkinDescriptor: Identifiable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let glyph: String            // single Space Mono character on the switcher
    let productID: String?       // nil = free, always entitled

    var isFree: Bool { productID == nil }
    var priceLabel: String { isFree ? "Free" : "$1" }
}

// Interactions are a closed enum, never free text — the attention report is
// aggregate-only and free text would drag personal content into it (§4).
enum SkinAction: String {
    case advance, back, complete, reset, toggle, mark
}

enum SkinCatalog {
    static let none = SkinDescriptor(
        id: "none", name: "No skin", tagline: "Clips, full height.",
        glyph: "—", productID: nil
    )

    static let all: [SkinDescriptor] = [
        SkinDescriptor(
            id: "tally", name: "The Tally", tagline: "Scout the contract while you watch.",
            glyph: "$", productID: nil
        ),
        SkinDescriptor(
            id: "cookbook", name: "Cookbook", tagline: "One recipe, one step at a time.",
            glyph: "☰", productID: "com.bountysounds.skin.cookbook"
        ),
        SkinDescriptor(
            id: "lyrics", name: "Lyric Sheet", tagline: "Mark the hook while you watch.",
            glyph: "♪", productID: "com.bountysounds.skin.lyrics"
        ),
    ]

    static func descriptor(id: String) -> SkinDescriptor {
        all.first { $0.id == id } ?? SkinCatalog.none
    }

    @ViewBuilder
    static func view(for id: String) -> some View {
        switch id {
        case "tally": TallySkin()
        case "cookbook": CookbookSkin()
        case "lyrics": LyricSheetSkin()
        default: EmptyView()
        }
    }
}

// Shared chrome so every skin sits in the same frame: title rule at the top,
// hairline underneath, content below. Skins supply only their content.
struct SkinFrame<Content: View>: View {
    let descriptor: SkinDescriptor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.card)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MonoLabel(text: descriptor.glyph, size: 10, tracking: 0.1, color: .ink, bold: true)
            Text(descriptor.name)
                .font(.serif(15, .semibold))
                .foregroundStyle(Color.ink)
            Spacer()
            MonoLabel(text: descriptor.tagline, size: 9, tracking: 0.12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 9)
    }
}
