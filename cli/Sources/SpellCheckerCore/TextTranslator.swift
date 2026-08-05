/// Which shape of answer the input deserves.
///
/// A short input is a vocabulary lookup — the developer wants meanings, not a
/// sentence. Anything longer is prose they want to read in Russian.
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

/// One Russian meaning of an English word, with teaching material.
///
/// The explanation and example are in **simple English** on purpose: the
/// translation answers "what does this mean", and the English around it is what
/// makes the meaning stick.
public struct WordMeaning: Sendable, Equatable, Codable {
    public let translation: String   // Russian
    public let explanation: String   // simple English
    public let example: String       // simple English

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
    /// Just the Russian.
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
    /// Translate English into Russian. The shape of the result follows
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

/// Text mode: the reply is used verbatim, so the prompt has to be strict about
/// returning nothing else. The user's text is appended after it.
let textTranslationPrompt = """
Translate the following English text into Russian. Reply with ONLY the Russian \
translation — no quotes, no transliteration, no commentary, no alternatives, and \
no explanation.

Text:
"""

/// Word mode: asks for minified JSON. Kept in sync with `parseWordResult` and
/// with the vault note Design/ad-hoc-translator.
let wordTranslationPrompt = """
You are helping a Russian-speaking software developer understand an English word \
or short phrase.

Give up to 3 of its most common meanings, most common first. For each meaning:
- "translation": the Russian translation
- "explanation": what this meaning means, in simple English, about 15 words
- "example": one short, natural English sentence using the word in this meaning

Set "hasMore" to true only if the word has further common meanings you left out.

Reply with ONLY minified JSON in exactly this shape — no markdown fences, no \
commentary:
{"meanings":[{"translation":"…","explanation":"…","example":"…"}],"hasMore":false}

Word:
"""
