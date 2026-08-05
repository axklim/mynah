import Foundation

/// Launch failure or a non-zero exit from the `claude` subprocess.
struct ClaudeCLIError: Error, CustomStringConvertible {
    let description: String
}

/// The one place that shells out to the Claude Code CLI in print mode:
/// `claude -p --model <model>`. Reuses the existing Claude Code auth, so no API
/// key is needed (Decision 0006).
///
/// Both hard-won lessons live here and nowhere else: resolving claude's absolute
/// path, because a Finder-launched `.app` does not inherit the interactive shell
/// PATH; and pinning the subprocess working directory to an empty app-private
/// folder, because claude inspects its CWD on startup — which triggered macOS
/// privacy prompts and could let a stray CLAUDE.md leak into a reply.
enum ClaudeCLI {
    /// Run claude with `prompt` on stdin and return stdout.
    ///
    /// - Parameter onStart: called with the live process immediately after launch.
    ///   Nothing uses it yet. It exists because slice 3's floating window must be
    ///   able to kill an in-flight call when the panel is dismissed, and Swift
    ///   `Task` cancellation cannot do that — the read below blocks in a way that
    ///   ignores it, so the caller needs the `Process` itself to terminate.
    static func run(
        prompt: String,
        model: String,
        onStart: ((Process) -> Void)? = nil
    ) throws -> String {
        let process = Process()
        // GUI apps don't inherit the shell PATH — resolve claude's absolute path,
        // falling back to `/usr/bin/env claude` for terminal runs.
        let claudeURL = resolveClaudeURL()
        process.executableURL = claudeURL
        process.arguments = claudeURL.lastPathComponent == "env"
            ? ["claude", "-p", "--model", model]
            : ["-p", "--model", model]

        // Run claude in an empty, app-private dir so it has no surrounding files to
        // scan or pick up context from — the reply depends only on the stdin prompt.
        // (Also reduces, but does not guarantee removal of, the macOS file-access
        // prompts a GUI launch can trigger — claude may probe user folders on its own.)
        process.currentDirectoryURL = claudeWorkingDirectory()

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ClaudeCLIError(description: "could not launch claude: \(error)")
        }
        onStart?(process)

        // Feed the prompt via stdin (avoids any shell quoting of user text).
        stdin.fileHandleForWriting.write(Data(prompt.utf8))
        try? stdin.fileHandleForWriting.close()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ClaudeCLIError(
                description: "claude exited with status \(process.terminationStatus): \(detail)"
            )
        }

        // Only stdout is the result; stderr may carry unrelated hook noise.
        return String(decoding: outData, as: UTF8.self)
    }

    /// Resolve the `claude` binary. A GUI `.app` launched from Finder does not
    /// inherit the interactive shell PATH, so check the known install locations
    /// first; otherwise fall back to `/usr/bin/env claude`, which resolves via
    /// PATH when run from a terminal.
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
    /// there could leak into the reply, and scanning user folders is exactly what
    /// we don't want. Application Support is not TCC-protected, and the stable
    /// path lets claude's workspace-trust persist.
    static func claudeWorkingDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("SpellChecker/claude-cwd", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
