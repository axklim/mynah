import Foundation

/// Evaluates text by shelling out to the Claude Code CLI in print mode:
/// `claude -p --model <model>`. Reuses the existing Claude Code auth, so no
/// API key is needed. See Decision 0006.
public struct ClaudeCLIEvaluator: TextEvaluator {
    /// Model alias passed to `claude --model`. Default `sonnet`: evaluation is the
    /// "analysis" task Decision 0001 earmarked for a stronger model, and Haiku
    /// under-detected ambiguity in testing (see Findings/haiku-misses-ambiguity).
    public var model: String

    public init(model: String = "sonnet") {
        self.model = model
    }

    public func evaluate(_ text: String) throws -> Verdict {
        let reply = try runClaude(prompt: evaluationPrompt + "\n\n" + text)
        return try Self.parseVerdict(from: reply)
    }

    /// Resolve the `claude` binary. A GUI `.app` launched from Finder does not
    /// inherit the interactive shell PATH, so check the known install locations
    /// first (this machine has it in ~/.local/bin); otherwise fall back to
    /// `/usr/bin/env claude`, which resolves via PATH when run from a terminal.
    static func resolveClaudeURL() -> URL {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/env")  // arguments still start with "claude"
    }

    /// An empty, app-private working directory for the claude subprocess.
    ///
    /// claude inspects its working directory on startup (git status, CLAUDE.md,
    /// directory listing), so the CWD must NOT be the shared `$TMPDIR` (full of
    /// other apps' files) or any real project/user folder — a stray CLAUDE.md
    /// there could leak into the verdict, and scanning user folders is exactly
    /// what we don't want. An empty, app-owned dir keeps the evaluation dependent
    /// only on the prompt we feed via stdin. Application Support is not
    /// TCC-protected, and the stable path lets claude's workspace-trust persist.
    static func claudeWorkingDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("SpellChecker/claude-cwd", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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

    private func runClaude(prompt: String) throws -> String {
        let process = Process()
        // GUI apps don't inherit the shell PATH — resolve claude's absolute path,
        // falling back to `/usr/bin/env claude` for terminal runs.
        let claudeURL = Self.resolveClaudeURL()
        process.executableURL = claudeURL
        process.arguments = claudeURL.lastPathComponent == "env"
            ? ["claude", "-p", "--model", model]
            : ["-p", "--model", model]

        // Run claude in an empty, app-private dir so it has no surrounding files to
        // scan or pick up context from — the verdict depends only on the stdin prompt.
        // (Also reduces, but does not guarantee removal of, the macOS file-access
        // prompts a GUI launch can trigger — claude may probe user folders on its own.)
        process.currentDirectoryURL = Self.claudeWorkingDirectory()

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
