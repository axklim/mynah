/// The two translation prompts, as functions of the configured language pair.
///
/// Kept in sync with `ClaudeCLITranslator.parseWordResult` and with the vault note
/// Design/configurable-language-pair.
enum TranslationPrompts {
    /// Prose mode: the reply is used verbatim, so the prompt has to be strict
    /// about returning nothing else. The user's text is appended after it.
    static func text(_ pair: LanguagePair) -> String {
        """
        Translate the following \(pair.source) text into \(pair.target). Reply with ONLY \
        the \(pair.target) translation — no quotes, no transliteration, no commentary, no \
        alternatives, and no explanation.

        Text:
        """
    }

    /// Word mode: asks for minified JSON.
    ///
    /// The translation is in the target language; the explanation and example are
    /// in the **source** language, kept simple. That is where the teaching value
    /// is — for the default English → German pair it is exactly the simple-English
    /// material the En → Ru version shipped with.
    ///
    /// There is deliberately no "you are helping a Russian-speaking developer"
    /// opening any more: with the pair configurable, the reader's native language
    /// is not derivable from it.
    static func word(_ pair: LanguagePair) -> String {
        """
        You are helping a software developer understand a \(pair.source) word or short phrase.

        Give up to 3 of its most common meanings, most common first. For each meaning:
        - "translation": the \(pair.target) translation
        - "explanation": what this meaning means, in simple \(pair.source), about 15 words
        - "example": one short, natural \(pair.source) sentence using the word in this meaning

        Set "hasMore" to true only if the word has further common meanings you left out.

        Reply with ONLY minified JSON in exactly this shape — no markdown fences, no \
        commentary:
        {"meanings":[{"translation":"…","explanation":"…","example":"…"}],"hasMore":false}

        Word:
        """
    }
}
