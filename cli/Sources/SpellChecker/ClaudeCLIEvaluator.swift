import Foundation

/// Evaluates text by shelling out to the Claude Code CLI in print mode:
/// `claude -p --model <model>`. Reuses the existing Claude Code auth, so no
/// API key is needed. See Decision 0006.
struct ClaudeCLIEvaluator: TextEvaluator {
    /// Model alias passed to `claude --model`. Default `sonnet`: evaluation is the
    /// "analysis" task Decision 0001 earmarked for a stronger model, and Haiku
    /// under-detected ambiguity in testing (see Findings/haiku-misses-ambiguity).
    var model = "sonnet"

    func evaluate(_ text: String) throws -> Verdict {
        let reply = try runClaude(prompt: evaluationPrompt + "\n\n" + text)
        return try parseVerdict(from: reply)
    }

    /// Scan the reply for the first standalone red / yellow / green token.
    /// Lenient on purpose — a stray emoji or word shouldn't break parsing — but
    /// matches whole words so substrings ("covered", "predicted") don't trip it.
    private func parseVerdict(from reply: String) throws -> Verdict {
        for token in reply.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let verdict = Verdict(rawValue: String(token)) {
                return verdict
            }
        }
        throw EvaluationError(
            description: "no verdict found in model reply: \(reply.debugDescription)"
        )
    }

    private func runClaude(prompt: String) throws -> String {
        let process = Process()
        // Resolve `claude` from PATH (it lives in ~/.local/bin).
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "-p", "--model", model]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw EvaluationError(description: "could not launch claude: \(error)")
        }

        // Feed the prompt via stdin (avoids any shell quoting of user text).
        stdin.fileHandleForWriting.write(Data(prompt.utf8))
        try? stdin.fileHandleForWriting.close()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw EvaluationError(
                description: "claude exited with status \(process.terminationStatus): \(detail)"
            )
        }

        // Only stdout is the result; stderr may carry unrelated hook noise.
        return String(decoding: outData, as: UTF8.self)
    }
}
