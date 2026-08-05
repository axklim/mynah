import Foundation

/// Translates English → Russian by asking Claude through `ClaudeCLI`.
public struct ClaudeCLITranslator: TextTranslator {
    /// Model alias passed to `claude --model`. Sonnet for both modes, matching the
    /// evaluator: Haiku under-performed on nuance in this project. Exposed so
    /// trying Haiku for text mode later is a one-line experiment.
    public var model: String

    /// Word mode never shows more than this many meanings; the rest are reported
    /// by `hasMore`.
    static let maxMeanings = 3

    public init(model: String = "sonnet") {
        self.model = model
    }

    public func translate(_ text: String) throws -> TranslationResult {
        switch TranslationMode.forInput(text) {
        case .text:
            let reply = try ClaudeCLI.run(
                prompt: textTranslationPrompt + "\n\n" + text,
                model: model
            )
            let translation = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translation.isEmpty else {
                throw TranslationError(description: "model returned an empty translation")
            }
            return .text(translation)

        case .word:
            let reply = try ClaudeCLI.run(
                prompt: wordTranslationPrompt + "\n\n" + text,
                model: model
            )
            return try Self.parseWordResult(from: reply)
        }
    }

    /// Decode word-mode JSON, leniently — in the same spirit as `parseVerdict`.
    ///
    /// Takes the slice from the first `{` to the last `}`, because claude wraps
    /// JSON in a markdown fence however firmly the prompt asks it not to. Every
    /// failure carries the raw reply: there is no `--raw` flag, so this message is
    /// the whole debugging path.
    static func parseWordResult(from reply: String) throws -> TranslationResult {
        /// Only the fields we asked for; `hasMore` is optional so a reply that
        /// omits it decodes rather than failing.
        struct Payload: Decodable {
            let meanings: [WordMeaning]
            let hasMore: Bool?
        }

        guard
            let start = reply.firstIndex(of: "{"),
            let end = reply.lastIndex(of: "}"),
            start < end
        else {
            throw TranslationError(
                description: "no JSON object in model reply: \(reply.debugDescription)"
            )
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(
                Payload.self,
                from: Data(reply[start...end].utf8)
            )
        } catch {
            throw TranslationError(
                description: "could not decode word JSON (\(error)): \(reply.debugDescription)"
            )
        }

        guard !payload.meanings.isEmpty else {
            throw TranslationError(
                description: "model returned no meanings: \(reply.debugDescription)"
            )
        }

        // Dropping a meaning is itself a reason to show the "more…" hint, whatever
        // the model claimed.
        if payload.meanings.count > maxMeanings {
            return .word(meanings: Array(payload.meanings.prefix(maxMeanings)), hasMore: true)
        }
        return .word(meanings: payload.meanings, hasMore: payload.hasMore ?? false)
    }
}
