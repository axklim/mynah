/// Evaluates text by asking Claude for one traffic-light verdict. The subprocess
/// handling lives in `ClaudeCLI`, shared with the translator.
public struct ClaudeCLIEvaluator: TextEvaluator {
    /// Model alias passed to `claude --model`. Default `sonnet`: evaluation is the
    /// "analysis" task Decision 0001 earmarked for a stronger model, and Haiku
    /// under-detected ambiguity in testing (see Findings/haiku-misses-ambiguity).
    public var model: String

    public init(model: String = "sonnet") {
        self.model = model
    }

    public func evaluate(_ text: String) throws -> Verdict {
        let reply = try ClaudeCLI.run(prompt: evaluationPrompt + "\n\n" + text, model: model)
        return try Self.parseVerdict(from: reply)
    }

    /// Scan the reply for the first standalone red / yellow / green token.
    /// Lenient on purpose — a stray emoji or word shouldn't break parsing — but
    /// matches whole words so substrings ("covered", "predicted") don't trip it.
    static func parseVerdict(from reply: String) throws -> Verdict {
        for token in reply.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let verdict = Verdict(rawValue: String(token)) {
                return verdict
            }
        }
        throw EvaluationError(
            description: "no verdict found in model reply: \(reply.debugDescription)"
        )
    }
}
