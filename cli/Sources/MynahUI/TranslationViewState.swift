import MynahCore

/// What the floating translation window is showing.
///
/// This lives in `MynahUI` rather than in the app target on purpose: the
/// mapping and every user-facing sentence are pure functions, and an executable
/// target cannot be imported by the test bundle. Slice 1 shipped a real defect of
/// exactly that shape — the mapping that told a green verdict from a red one had
/// no test, so a swapped case would have looked fine.
public enum TranslationViewState: Sendable, Equatable {
    /// The 文A glyph and "Translating…", while the call is in flight.
    case loading
    /// Prose mode: the Russian alone. The English was copied a second ago;
    /// reprinting it is noise.
    case text(String)
    /// Word mode: the source as a header, then up to three meanings.
    case word(source: String, meanings: [WordMeaning], hasMore: Bool)
    /// A guard rejection or a backend failure, phrased as a sentence.
    case failed(String)

    /// Map a finished translation onto the view.
    public static func from(_ result: TranslationResult, source: String) -> TranslationViewState {
        switch result {
        case .text(let russian):
            return .text(russian)
        case .word(let meanings, let hasMore):
            return .word(source: source, meanings: meanings, hasMore: hasMore)
        }
    }

    /// Map an input rejection onto the view, or nil when the input was fine.
    ///
    /// The translator reports rejections **in the window**, never in the menu-bar
    /// icon — the panel is its UI, and an icon that blinked while no window opened
    /// would be a worse explanation than none.
    public static func rejection(_ check: InputCheck) -> TranslationViewState? {
        switch check {
        case .ok:
            return nil
        case .noText:
            return .failed("Nothing to translate — the clipboard has no text.")
        case .tooLong(let count):
            return .failed(
                "That's \(count) characters, over the \(InputText.characterLimit) limit — "
                    + "did you mean to copy that much?"
            )
        }
    }

    /// Map a backend failure onto the view. The detail is kept: "it didn't work"
    /// with no reason is the least useful thing an error can say.
    public static func failure(_ error: Error) -> TranslationViewState {
        .failed("Couldn't reach claude. \(error)")
    }
}
