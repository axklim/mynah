/// Which shape of answer the input deserves.
///
/// A short input is a vocabulary lookup — the developer wants meanings, not a
/// sentence. Anything longer is prose they want to read in the target language.
public enum TranslationMode: Sendable, Equatable {
    /// 1–2 words: up to three meanings, each explained with an example.
    case word
    /// 3 or more words: the translation alone.
    case text

    /// Splits on whitespace, ignoring empty runs, so odd spacing cannot change
    /// the mode. Empty input reports `.word`; the CLI never reaches that, because
    /// `InputText.check` rejects empty input before this is consulted.
    public static func forInput(_ text: String) -> TranslationMode {
        text.split(whereSeparator: { $0.isWhitespace }).count <= 2 ? .word : .text
    }
}

/// One target-language meaning of a source-language word, with teaching material.
///
/// The explanation and example are in **simple source-language** prose on purpose:
/// the translation answers "what does this mean", and the source-language text
/// around it is what makes the meaning stick.
public struct WordMeaning: Sendable, Equatable, Codable {
    public let translation: String   // target language
    public let explanation: String   // simple source language
    public let example: String       // simple source language

    public init(translation: String, explanation: String, example: String) {
        self.translation = translation
        self.explanation = explanation
        self.example = example
    }
}

/// What a translation produced, shaped by `TranslationMode`.
public enum TranslationResult: Sendable, Equatable {
    /// 1–3 meanings, most common first. `hasMore` is the passive "more…" signal:
    /// the word has further common meanings that were left out.
    case word(meanings: [WordMeaning], hasMore: Bool)
    /// Just the translation.
    case text(String)
}

/// The model replied, but the reply could not be turned into a result.
struct TranslationError: Error, CustomStringConvertible {
    let description: String
}

/// The second backend-swap point, beside `TextEvaluator` (Decision 0006).
/// Today: `ClaudeCLITranslator`. A litellm / Gemini backend can conform later
/// without touching the CLI or the panel.
public protocol TextTranslator: Sendable {
    /// Translate from the configured source language into the target. The shape of the result follows
    /// `TranslationMode.forInput(text)`.
    ///
    /// - Parameter onStart: called once the work is under way, with a handle that
    ///   cancels it. Invoked on whatever thread the translation runs on, so a
    ///   main-actor caller must hop before touching UI state. The floating window
    ///   uses this to kill an in-flight call when it is dismissed.
    func translate(
        _ text: String,
        onStart: (@Sendable (TranslationHandle) -> Void)?
    ) throws -> TranslationResult
}

public extension TextTranslator {
    /// Translate without taking a cancellation handle — the CLI's case, where the
    /// process lives exactly as long as the command does.
    func translate(_ text: String) throws -> TranslationResult {
        try translate(text, onStart: nil)
    }
}
