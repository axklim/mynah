/// The evaluation instruction. The user's message is appended after it.
/// Keep the criteria here in sync with the vault note Design/traffic-light-eval.
let evaluationPrompt = """
You are evaluating a message written by a non-native English speaker who wants to know whether \
it is ready to send. Decide the verdict by whether a reader will correctly understand the \
intended meaning — not by how many mistakes there are. Reply with EXACTLY ONE word and nothing \
else:

- green — clear, natural, and free of real issues; safe to send as is.
- yellow — the meaning is clear, but the wording is awkward or non-native, or has grammar or \
spelling mistakes worth fixing. Any number of mistakes stays yellow as long as the meaning is \
not in doubt.
- red — a reader might misunderstand it: the meaning is genuinely unclear, ambiguous, has a \
double meaning, or could be read the wrong way.

Reply with only one word: red, yellow, or green. Do not explain.

Message:
"""

struct EvaluationError: Error, CustomStringConvertible {
    let description: String
}

/// One swap point for the LLM backend.
///
/// Today: `ClaudeCLIEvaluator` (shells out to `claude -p`). Later: a litellm /
/// Gemini backend conforms to the same protocol — see Decision 0006.
public protocol TextEvaluator: Sendable {
    /// Returns a single traffic-light verdict for `text`.
    func evaluate(_ text: String) throws -> Verdict
}
