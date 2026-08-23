import SwiftUI

// The skin the whole idea started from: one recipe, one step at a time, run
// with your thumb while the feed plays underneath. Steps are deliberately
// short — anything longer than a glance loses to the video.
struct CookbookSkin: View {
    @EnvironmentObject var stage: StageModel
    @State private var step = 0
    @State private var done: Set<Int> = []

    private var descriptor: SkinDescriptor { SkinCatalog.descriptor(id: "cookbook") }
    private var recipe: Recipe { Recipe.weeknightRagu }
    private var isLast: Bool { step == recipe.steps.count - 1 }

    var body: some View {
        SkinFrame(descriptor: descriptor) {
            VStack(alignment: .leading, spacing: 0) {
                title
                stepBody
                Spacer(minLength: 8)
                controls
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(recipe.name)
                .font(.serif(16, .semibold))
                .foregroundStyle(Color.ink)
            Spacer()
            MonoLabel(text: "Step \(step + 1) / \(recipe.steps.count)", size: 9, tracking: 0.18)
        }
        .padding(.bottom, 10)
    }

    private var stepBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipe.steps[step].instruction)
                .font(.grotesk(15))
                .foregroundStyle(Color.bodyText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let note = recipe.steps[step].note {
                MonoLabel(text: note, size: 9, tracking: 0.14)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            StampButton(title: "Back", fill: .clear, textColor: .ink, minHeight: 46, fontSize: 12) {
                guard step > 0 else { return }
                step -= 1
                stage.record(.back)
            }
            .opacity(step == 0 ? 0.35 : 1)
            .disabled(step == 0)

            StampButton(
                title: isLast ? "Done" : "Next",
                fill: isLast ? .olive : .ink,
                minHeight: 46, fontSize: 12
            ) {
                done.insert(step)
                if isLast {
                    stage.record(.complete)
                } else {
                    step += 1
                    stage.record(.advance)
                }
            }
        }
    }
}

struct Recipe {
    struct Step { let instruction: String; let note: String? }
    let name: String
    let steps: [Step]

    static let weeknightRagu = Recipe(name: "Weeknight ragù", steps: [
        Step(instruction: "Dice one onion, two carrots, two sticks of celery. Small — they should disappear.",
             note: "Five minutes of knife work buys you the whole sauce"),
        Step(instruction: "Sweat them in olive oil over low heat until soft and sweet, about 10 minutes.",
             note: "No colour yet"),
        Step(instruction: "Raise the heat. Add 500g beef mince and break it up until browned all over.", note: nil),
        Step(instruction: "Splash in a glass of red wine and let it cook off completely.",
             note: "Wait for the smell to turn from sharp to round"),
        Step(instruction: "Add a tin of tomatoes, a cup of stock, a bay leaf. Bring to a bare simmer.", note: nil),
        Step(instruction: "Leave it 45 minutes, stirring when you remember. Salt at the end, not the start.",
             note: "This is the part you scroll through"),
        Step(instruction: "Toss with pasta and a spoonful of the pasta water. Grate over more cheese than feels sensible.",
             note: "Serves four"),
    ])
}
