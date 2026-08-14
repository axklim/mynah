import SwiftUI
import MynahCore

/// Sizes shared by the view and the panel that hosts it.
///
/// Starting points to be judged on screen, like the status icon's baseline nudge:
/// 420pt is wide enough for a Russian sentence without becoming a paragraph, and
/// the height cap is what keeps 2000 characters of translation from running off
/// the bottom of the display.
public enum TranslationPanelMetrics {
    public static let width: CGFloat = 420
    public static let maxHeight: CGFloat = 520
}

/// The floating window's content.
public struct TranslationView: View {
    private let state: TranslationViewState

    public init(state: TranslationViewState) {
        self.state = state
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        // Body text is the system font: the Nerd Font is for icon glyphs only.
        .font(.body)
        // Settles the copy question without a button — ⌘C works on a selection.
        .textSelection(.enabled)
        .frame(width: TranslationPanelMetrics.width)
        .frame(maxHeight: TranslationPanelMetrics.maxHeight)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                Text(IconState.translating.glyph)
                    .font(.custom(IconFont.postScriptName, size: 15))
                Text("Translating…")
                    .foregroundStyle(.secondary)
            }

        case .text(let translation):
            Text(translation)
                .textSelection(.enabled)

        case .word(let source, let meanings, let hasMore):
            Text(source)
                .font(.title3.weight(.semibold))
            ForEach(Array(meanings.enumerated()), id: \.offset) { index, meaning in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(index + 1). \(meaning.translation)")
                        .font(.body.weight(.medium))
                    Text(meaning.explanation)
                        .foregroundStyle(.secondary)
                    Text("\u{201C}\(meaning.example)\u{201D}")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            if hasMore {
                Text("more meanings exist")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

        case .failed(let message):
            Text(message)
        }
    }
}
