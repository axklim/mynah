# Translator Slice 2 — `spell-checker translate` (En → Ru)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add English → Russian translation to `SpellCheckerCore` and expose it as `spell-checker translate`, so the prompts can be tuned in a terminal before any GUI exists.

**Architecture:** The `claude -p` shell-out moves out of `ClaudeCLIEvaluator` into a shared internal `ClaudeCLI`, so the evaluator and the new translator both use one copy of the PATH and working-directory handling. A `TextTranslator` protocol sits beside `TextEvaluator` as the second backend-swap point. Input length decides the shape of the answer: 1–2 words gets up to three meanings with simple-English explanations (asked for as JSON), 3+ words gets the translation alone (plain text, nothing to parse).

**Tech Stack:** Swift 6, SwiftPM (no Xcode project), XCTest, Foundation, `make`.

**Spec:** `spell-checker-vault/Design/ad-hoc-translator.md`, the "Slice 2" section. Slice 1 shipped on `main` as `e141393`. The floating window is **slice 3** and gets its own plan.

## Global Constraints

- **Branch:** `translator-slice-2` (already created from `main`). Never commit to `main`. Never `git commit --amend`, never rewrite history. Do not push.
- **Commit titles:** plain descriptive, **no ticket prefix** (repo is under `~/pet`). **Every commit message must end with** `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- **Swift 6**, platform floor **macOS 13**. **No new package dependencies.**
- **`SpellCheckerCore` contains no AppKit and no SwiftUI.** Foundation is fine. **Every file imports what it uses** — Swift imports are file-scoped, and slice 1 shipped a file that compiled only because a sibling's import leaked across the module. If a new file calls Foundation APIs, it declares `import Foundation` itself.
- **Input limits are not re-implemented.** `InputText.check(_:)` already exists in Core with `characterLimit == 2000`; `translate` reuses it exactly as `check` does. `.ok` carries the trimmed string — use that value, never re-trim.
- **Model: `sonnet`** for both modes, exposed as `var model` (Haiku under-performed on nuance in this project — `Findings/haiku-misses-ambiguity`).
- **Word mode caps at 3 meanings.** More than three in a reply → keep the first three and force `hasMore = true`.
- **Tests:** XCTest, in the existing `cli/Tests/SpellCheckerCoreTests/`. Run with `make test` from the repo root. The suite is at **23 tests** before this slice.
- **Real `claude` calls cost money and take seconds.** Manual verification steps say exactly which calls to make; do not add extra ones, and do not loop.

---

## File Structure

**Create:**
- `cli/Sources/SpellCheckerCore/ClaudeCLI.swift` — the one place that launches `claude -p`. Internal.
- `cli/Sources/SpellCheckerCore/TextTranslator.swift` — the `TextTranslator` protocol, `TranslationMode`, `WordMeaning`, `TranslationResult`, `TranslationError`, and the two prompts (mirrors how `TextEvaluator.swift` holds the protocol beside `evaluationPrompt`).
- `cli/Sources/SpellCheckerCore/ClaudeCLITranslator.swift` — the conforming type: prompt selection, `ClaudeCLI` call, `parseWordResult`.
- `cli/Sources/SpellCheckerCore/TranslationResult+Terminal.swift` — pure text rendering for the CLI.
- `cli/Tests/SpellCheckerCoreTests/TranslationModeTests.swift`
- `cli/Tests/SpellCheckerCoreTests/ParseWordResultTests.swift`
- `cli/Tests/SpellCheckerCoreTests/TranslationTerminalTests.swift`

**Modify:**
- `cli/Sources/SpellCheckerCore/ClaudeCLIEvaluator.swift` — drops the process plumbing, keeps `evaluate` and `parseVerdict`.
- `cli/Sources/SpellChecker/main.swift` — new `translate` subcommand and its usage line.
- `CLAUDE.md`, `cli/README.md`, `README.md`, `spell-checker-vault/Design/ad-hoc-translator.md`, `spell-checker-vault/Roadmap.md` — document the new command (final task).

**Why the renderer lives in Core.** Slice 1's final review found a real defect in exactly this shape: presentation logic sitting in a target SwiftPM cannot import, where no test could reach it. `TranslationResult+Terminal.swift` is pure string formatting with no UI dependency, so Core can hold it without touching the no-UI-frameworks rule, and the numbered word-mode format gets tests.

---

### Task 1: Extract `ClaudeCLI` from the evaluator

A pure refactor. The translator needs the same subprocess handling, and copying it is how one copy drifts and only one caller breaks months later.

**Files:**
- Create: `cli/Sources/SpellCheckerCore/ClaudeCLI.swift`
- Modify: `cli/Sources/SpellCheckerCore/ClaudeCLIEvaluator.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ClaudeCLI.run(prompt: String, model: String, onStart: ((Process) -> Void)? = nil) throws -> String`, plus `ClaudeCLI.resolveClaudeURL() -> URL` and `ClaudeCLI.claudeWorkingDirectory() -> URL`, all **internal** (Core-only). Also `ClaudeCLIError`, an internal `Error & CustomStringConvertible` for launch and exit failures. `ClaudeCLIEvaluator.parseVerdict(from:)` and `evaluate(_:)` keep their current signatures.

- [ ] **Step 1: Create `ClaudeCLI.swift`**

Move the three pieces out of `ClaudeCLIEvaluator` verbatim, keeping every comment — they record two lessons that cost real debugging time:

```swift
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
```

- [ ] **Step 2: Shrink `ClaudeCLIEvaluator.swift` to prompt + parse**

Delete `runClaude(prompt:)`, `resolveClaudeURL()` and `claudeWorkingDirectory()` from it, and route `evaluate` through `ClaudeCLI`. The whole file becomes:

```swift
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
```

Note the file no longer needs `import Foundation` — nothing left in it touches Foundation. Per the global constraints, **remove the import if and only if the file compiles without it**; if the build complains, keep it. Do not remove `import Foundation` from any other file.

`EvaluationError` stays where it is, in `TextEvaluator.swift`, and still covers "the model replied but I could not parse it". Launch and exit failures now surface as `ClaudeCLIError`. No test asserts either error's type — `ParseVerdictTests.testNoVerdictThrows` uses an untyped `XCTAssertThrowsError` — and both conform to `CustomStringConvertible` with unchanged message text, so `main.swift`'s `error: \(error)` output is byte-identical.

- [ ] **Step 3: Run the suite — nothing should change**

Run: `make test`
Expected: **23 tests, 0 failures** — exactly the count before this task. This is a refactor; a changed count means something moved that shouldn't have.

- [ ] **Step 4: Regression-check the real evaluator**

One real `claude` call, because the point of this task is that the subprocess still launches correctly:

```bash
cd cli && swift run spell-checker check "Thanks for the review, I've merged the branch."
```

Expected: `🟢 green`. If it prints an error mentioning `could not launch claude`, the path resolution did not survive the move — fix before continuing.

- [ ] **Step 5: Commit**

```bash
git add cli/Sources/SpellCheckerCore/ClaudeCLI.swift cli/Sources/SpellCheckerCore/ClaudeCLIEvaluator.swift
git commit -m "refactor: extract the claude shell-out into ClaudeCLI

The translator needs the same subprocess handling, and duplicating it is how one
copy drifts and only one caller breaks. The PATH resolution and the empty
app-private working directory now live in exactly one place. Adds an onStart hook
for slice 3, which must be able to terminate an in-flight call.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `TranslationMode` — word or text

**Files:**
- Create: `cli/Sources/SpellCheckerCore/TextTranslator.swift`
- Test: `cli/Tests/SpellCheckerCoreTests/TranslationModeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `TranslationMode` (`.word` / `.text`, `Sendable & Equatable`) with `static func forInput(_ text: String) -> TranslationMode`. Later tasks add the protocol, the value types and the prompts to this same file.

- [ ] **Step 1: Write the failing tests**

Create `cli/Tests/SpellCheckerCoreTests/TranslationModeTests.swift`:

```swift
import XCTest
@testable import SpellCheckerCore

final class TranslationModeTests: XCTestCase {
    func testSingleWordIsWordMode() {
        XCTAssertEqual(TranslationMode.forInput("commit"), .word)
    }

    func testTwoWordsIsWordMode() {
        // A place name and a phrasal verb are both worth explaining as a unit.
        XCTAssertEqual(TranslationMode.forInput("New York"), .word)
        XCTAssertEqual(TranslationMode.forInput("look up"), .word)
    }

    func testHyphenatedWordIsOneWord() {
        XCTAssertEqual(TranslationMode.forInput("well-known"), .word)
    }

    func testThreeWordsIsTextMode() {
        XCTAssertEqual(TranslationMode.forInput("commit the change"), .text)
    }

    func testOddWhitespaceDoesNotChangeTheMode() {
        // Runs of spaces, tabs and newlines must not be counted as words.
        XCTAssertEqual(TranslationMode.forInput("  commit   the   change  "), .text)
        XCTAssertEqual(TranslationMode.forInput("commit\nthe\tchange"), .text)
        XCTAssertEqual(TranslationMode.forInput("  commit  "), .word)
    }

    func testEmptyInputIsWordMode() {
        // Unreachable through the CLI — InputText rejects empty input first — but
        // pinned so the split logic can never fall through to a crash.
        XCTAssertEqual(TranslationMode.forInput(""), .word)
        XCTAssertEqual(TranslationMode.forInput("   "), .word)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd cli && swift test --filter TranslationModeTests`
Expected: compile failure, `cannot find 'TranslationMode' in scope`.

- [ ] **Step 3: Create `TextTranslator.swift` with the mode**

```swift
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd cli && swift test --filter TranslationModeTests`
Expected: **6 tests passing.**

- [ ] **Step 5: Commit**

```bash
git add cli/Sources/SpellCheckerCore/TextTranslator.swift cli/Tests/SpellCheckerCoreTests/TranslationModeTests.swift
git commit -m "feat: add TranslationMode to split word lookups from prose

1-2 words is a vocabulary lookup and gets meanings; 3+ is prose and gets the
translation alone. Splitting on whitespace runs means odd spacing cannot change
the mode.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Translation types and the lenient JSON parse

**Files:**
- Modify: `cli/Sources/SpellCheckerCore/TextTranslator.swift` — add the protocol, value types, error, and prompts
- Create: `cli/Sources/SpellCheckerCore/ClaudeCLITranslator.swift` — the type and its `parseWordResult`
- Test: `cli/Tests/SpellCheckerCoreTests/ParseWordResultTests.swift`

**Interfaces:**
- Consumes: `TranslationMode` from Task 2; `ClaudeCLI.run` from Task 1 (used in Task 4, not here).
- Produces: `TextTranslator` protocol with `func translate(_ text: String) throws -> TranslationResult`; `WordMeaning` (`translation`, `explanation`, `example`; `Sendable, Equatable, Codable`); `TranslationResult` (`.word(meanings: [WordMeaning], hasMore: Bool)` / `.text(String)`, `Sendable, Equatable`); `TranslationError`; `textTranslationPrompt` and `wordTranslationPrompt` at file scope; `ClaudeCLITranslator.maxMeanings == 3`; `ClaudeCLITranslator.parseWordResult(from: String) throws -> TranslationResult`.

- [ ] **Step 1: Write the failing tests**

Create `cli/Tests/SpellCheckerCoreTests/ParseWordResultTests.swift`:

```swift
import XCTest
@testable import SpellCheckerCore

final class ParseWordResultTests: XCTestCase {
    private func meanings(_ result: TranslationResult) -> [WordMeaning] {
        guard case .word(let meanings, _) = result else {
            XCTFail("expected word mode, got \(result)")
            return []
        }
        return meanings
    }

    private func hasMore(_ result: TranslationResult) -> Bool {
        guard case .word(_, let hasMore) = result else {
            XCTFail("expected word mode, got \(result)")
            return false
        }
        return hasMore
    }

    func testCleanJSON() throws {
        let reply = """
        {"meanings":[{"translation":"фиксация","explanation":"saving your changes into history","example":"I commit before lunch."}],"hasMore":false}
        """
        let result = try ClaudeCLITranslator.parseWordResult(from: reply)
        XCTAssertEqual(meanings(result).count, 1)
        XCTAssertEqual(meanings(result)[0].translation, "фиксация")
        XCTAssertEqual(meanings(result)[0].example, "I commit before lunch.")
        XCTAssertFalse(hasMore(result))
    }

    func testFencedJSON() throws {
        // claude wraps JSON in a markdown fence however firmly you ask it not to.
        let reply = """
        ```json
        {"meanings":[{"translation":"фиксация","explanation":"a saved change","example":"One commit per fix."}],"hasMore":true}
        ```
        """
        let result = try ClaudeCLITranslator.parseWordResult(from: reply)
        XCTAssertEqual(meanings(result).count, 1)
        XCTAssertTrue(hasMore(result))
    }

    func testJSONBehindLeadingProse() throws {
        let reply = """
        Here is the JSON you asked for:
        {"meanings":[{"translation":"обязательство","explanation":"a promise to do something","example":"That is a big commit of time."}],"hasMore":false}
        Hope that helps!
        """
        let result = try ClaudeCLITranslator.parseWordResult(from: reply)
        XCTAssertEqual(meanings(result)[0].translation, "обязательство")
    }

    func testMoreThanThreeMeaningsIsClampedAndForcesHasMore() throws {
        let one = #"{"translation":"a","explanation":"e","example":"x"}"#
        let reply = #"{"meanings":[\#(one),\#(one),\#(one),\#(one)],"hasMore":false}"#
        let result = try ClaudeCLITranslator.parseWordResult(from: reply)
        XCTAssertEqual(meanings(result).count, ClaudeCLITranslator.maxMeanings)
        XCTAssertTrue(hasMore(result), "dropping a meaning must be reported as more existing")
    }

    func testMissingHasMoreDefaultsToFalse() throws {
        let reply = #"{"meanings":[{"translation":"a","explanation":"e","example":"x"}]}"#
        XCTAssertFalse(hasMore(try ClaudeCLITranslator.parseWordResult(from: reply)))
    }

    func testZeroMeaningsThrows() {
        XCTAssertThrowsError(
            try ClaudeCLITranslator.parseWordResult(from: #"{"meanings":[],"hasMore":false}"#)
        )
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try ClaudeCLITranslator.parseWordResult(from: "{not json at all}"))
    }

    func testReplyWithNoJSONThrows() {
        XCTAssertThrowsError(try ClaudeCLITranslator.parseWordResult(from: "I cannot help with that."))
    }

    func testErrorMessageCarriesTheRawReply() {
        // The error text is the whole debugging path — no --raw flag exists.
        let reply = "I cannot help with that."
        do {
            _ = try ClaudeCLITranslator.parseWordResult(from: reply)
            XCTFail("expected a throw")
        } catch {
            XCTAssertTrue("\(error)".contains("cannot help"), "raw reply missing from: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd cli && swift test --filter ParseWordResultTests`
Expected: compile failure — `ClaudeCLITranslator`, `TranslationResult` and `WordMeaning` do not exist yet.

- [ ] **Step 3: Add the types and prompts to `TextTranslator.swift`**

Append to the file created in Task 2:

```swift
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
/// without touching the CLI.
public protocol TextTranslator: Sendable {
    /// Translate English into Russian. The shape of the result follows
    /// `TranslationMode.forInput(text)`.
    func translate(_ text: String) throws -> TranslationResult
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
```

- [ ] **Step 4: Create `ClaudeCLITranslator.swift` with the parser only**

`translate` arrives in Task 4; this step is the parse plus the type it hangs on. A stub `translate` keeps the protocol conformance honest without pretending to work:

```swift
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
        throw TranslationError(description: "not implemented yet")
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
```

- [ ] **Step 5: Run to verify the parse tests pass**

Run: `cd cli && swift test --filter ParseWordResultTests`
Expected: **9 tests passing.**

- [ ] **Step 6: Run the whole suite**

Run: `make test`
Expected: **38 tests, 0 failures** (23 before this slice + 6 mode + 9 parse).

- [ ] **Step 7: Commit**

```bash
git add cli/Sources/SpellCheckerCore/TextTranslator.swift cli/Sources/SpellCheckerCore/ClaudeCLITranslator.swift cli/Tests/SpellCheckerCoreTests/ParseWordResultTests.swift
git commit -m "feat: add translation types and lenient word-mode JSON parsing

Text mode needs no parsing; word mode asks for JSON and decodes the slice from
the first brace to the last, because claude fences JSON however firmly you ask it
not to. Over three meanings are clamped and force hasMore, since dropping one is
itself a reason to show the hint. Every failure carries the raw reply — that
message is the only debugging path.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Wire `translate` to Claude

**Files:**
- Modify: `cli/Sources/SpellCheckerCore/ClaudeCLITranslator.swift` — replace the stub

**Interfaces:**
- Consumes: `ClaudeCLI.run(prompt:model:onStart:)`, `TranslationMode.forInput`, `parseWordResult`, both prompts.
- Produces: a working `ClaudeCLITranslator.translate(_:)`.

No new unit tests: this method's only logic is choosing a prompt and delegating, and both destinations are already covered. Its real risk is prompt *quality*, which fixtures cannot judge — Step 2 reads real output instead.

- [ ] **Step 1: Replace the stub**

```swift
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
```

- [ ] **Step 2: Build and confirm the suite is unaffected**

Run: `make test`
Expected: **38 tests, 0 failures**, clean build with no warnings.

- [ ] **Step 3: Commit**

```bash
git add cli/Sources/SpellCheckerCore/ClaudeCLITranslator.swift
git commit -m "feat: implement translate via ClaudeCLI

Mode chooses the prompt: text mode returns the reply verbatim after trimming,
word mode goes through the JSON parse.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The `translate` subcommand

**Files:**
- Create: `cli/Sources/SpellCheckerCore/TranslationResult+Terminal.swift`
- Test: `cli/Tests/SpellCheckerCoreTests/TranslationTerminalTests.swift`
- Modify: `cli/Sources/SpellChecker/main.swift`

**Interfaces:**
- Consumes: `TranslationResult`, `WordMeaning`, `ClaudeCLITranslator`, `InputText.check`.
- Produces: `TranslationResult.terminalText(source: String) -> String`, and the CLI's `translate` subcommand.

- [ ] **Step 1: Write the failing renderer tests**

Create `cli/Tests/SpellCheckerCoreTests/TranslationTerminalTests.swift`:

```swift
import XCTest
@testable import SpellCheckerCore

final class TranslationTerminalTests: XCTestCase {
    func testTextModePrintsTheRussianAlone() {
        // So `pbpaste | spell-checker translate | pbcopy` round-trips cleanly.
        let result = TranslationResult.text("Привет, мир.")
        XCTAssertEqual(result.terminalText(source: "Hello, world."), "Привет, мир.")
    }

    func testWordModeIsNumberedWithQuotedExamples() {
        let result = TranslationResult.word(
            meanings: [
                WordMeaning(
                    translation: "фиксация",
                    explanation: "saving your changes into the repository history",
                    example: "I commit my changes before lunch."
                ),
                WordMeaning(
                    translation: "обязательство",
                    explanation: "a promise to do something",
                    example: "This is a big commit of time."
                ),
            ],
            hasMore: false
        )
        XCTAssertEqual(result.terminalText(source: "commit"), """
        commit
          1. фиксация — saving your changes into the repository history
             "I commit my changes before lunch."
          2. обязательство — a promise to do something
             "This is a big commit of time."
        """)
    }

    func testMoreLineAppearsOnlyWhenHasMore() {
        let one = WordMeaning(translation: "а", explanation: "e", example: "x")
        let without = TranslationResult.word(meanings: [one], hasMore: false)
        let with = TranslationResult.word(meanings: [one], hasMore: true)
        XCTAssertFalse(without.terminalText(source: "a").contains("more meanings exist"))
        XCTAssertTrue(with.terminalText(source: "a").hasSuffix("  … more meanings exist"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd cli && swift test --filter TranslationTerminalTests`
Expected: compile failure, `value of type 'TranslationResult' has no member 'terminalText'`.

- [ ] **Step 3: Write the renderer**

Create `cli/Sources/SpellCheckerCore/TranslationResult+Terminal.swift`:

```swift
public extension TranslationResult {
    /// Render for a terminal.
    ///
    /// Text mode prints the Russian and nothing else, so the output can be piped
    /// straight into `pbcopy`. Word mode prints the source word as a header, then
    /// numbered meanings with the example quoted underneath.
    ///
    /// This lives in Core rather than in the CLI target because it is pure string
    /// work with no UI dependency, and an executable target cannot be imported by
    /// the test bundle — slice 1 learned that the hard way when an untestable
    /// mapping turned out to be the only thing distinguishing a green verdict from
    /// a red one.
    func terminalText(source: String) -> String {
        switch self {
        case .text(let russian):
            return russian

        case .word(let meanings, let hasMore):
            var lines = [source]
            for (index, meaning) in meanings.enumerated() {
                lines.append("  \(index + 1). \(meaning.translation) — \(meaning.explanation)")
                lines.append("     \"\(meaning.example)\"")
            }
            if hasMore {
                lines.append("  … more meanings exist")
            }
            return lines.joined(separator: "\n")
        }
    }
}
```

- [ ] **Step 4: Run to verify the renderer tests pass**

Run: `cd cli && swift test --filter TranslationTerminalTests`
Expected: **3 tests passing.**

- [ ] **Step 5: Add the subcommand to `main.swift`**

Extend the `usage` string — insert these two lines after the existing `check` lines, keeping the alignment:

```
  spell-checker translate <text>  Translate English → Russian
  spell-checker translate        Read the text from stdin
```

Then add this case to the `switch args.first`, directly after the `case "check":` block ends and before `case .none:`:

```swift
case "translate":
    let rest = Array(args.dropFirst())
    let raw = rest.isEmpty
        ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        : rest.joined(separator: " ")

    let source: String
    switch InputText.check(raw) {
    case .ok(let trimmed):
        source = trimmed
    case .noText:
        fail("usage: spell-checker translate <text>   (or pipe text via stdin)", code: 2)
    case .tooLong(let count):
        fail(
            """
            error: input is \(count) characters, limit is \(InputText.characterLimit)
            That looks like an accidental paste — check what you copied.
            """,
            code: 2
        )
    }

    let translator: TextTranslator = ClaudeCLITranslator()
    do {
        emit(try translator.translate(source).terminalText(source: source), to: .standardOutput)
    } catch {
        fail("error: \(error)", code: 1)
    }
```

Exit codes match `check`: **2** for either input rejection, **1** for a translator failure.

*(Corrected during execution.* The code above duplicates `check`'s entire input-guard block, which the task review flagged — including two copies of the character-limit message, so changing the limit or its wording means finding both. This project already shipped that exact shape once, in slice 1's duplicated font-name literal. The guard is now hoisted into a `requireInput(_ rest: [String], usage hint: String) -> String` helper in `main.swift`, which both subcommands call; each case keeps only its distinct tail. The `usage` block's description column was also misaligned by one space in the text above, and is now aligned across all five entries.*)

- [ ] **Step 6: Verify by hand — four real calls, no more**

```bash
cd cli
swift run spell-checker translate "commit"
```
Expected: `commit` as a header, then up to three numbered Russian meanings, each with a simple-English explanation and a quoted example. Read them: the explanations should be plain English of roughly 15 words, not dictionary-speak. If a polysemous word yields only one meaning, the word prompt needs work — that is exactly what this step is for.

```bash
swift run spell-checker translate "Could you take a look at my PR when you have a moment?"
```
Expected: **one** Russian sentence, nothing else — no quotes around it, no transliteration, no "Here is the translation".

```bash
swift run spell-checker translate "New York"
```
Expected: word mode, sensible output. A place name legitimately has one meaning and `hasMore: false`.

```bash
printf '' | swift run spell-checker translate; echo "exit=$?"
printf 'a%.0s' $(seq 2001) | swift run spell-checker translate; echo "exit=$?"
```
Expected: the usage message then `exit=2`; then the character-count message naming 2001 and 2000, then `exit=2`. The second must return **instantly** — no LLM call.

Finally the pipe that motivated text mode's format:

```bash
echo "Thanks for the review, I have merged the branch." | swift run spell-checker translate | pbcopy && pbpaste
```
Expected: only Russian on the clipboard.

- [ ] **Step 7: Commit**

```bash
git add cli/Sources/SpellCheckerCore/TranslationResult+Terminal.swift cli/Tests/SpellCheckerCoreTests/TranslationTerminalTests.swift cli/Sources/SpellChecker/main.swift
git commit -m "feat: add spell-checker translate

Text mode prints the Russian alone so it pipes into pbcopy; word mode prints
numbered meanings with quoted examples and a trailing hint when more exist. The
renderer lives in Core so it can be tested — an executable target cannot be
imported by the test bundle. Input rejections reuse the shared guard and exit 2.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Document the new command

**Files:**
- Modify: `CLAUDE.md`, `cli/README.md`, `README.md`, `spell-checker-vault/Design/ad-hoc-translator.md`, `spell-checker-vault/Roadmap.md`

- [ ] **Step 1: Update the two READMEs and `CLAUDE.md`**

Exact text, so the wording does not drift between the three files.

**`CLAUDE.md`** — insert directly after the existing `- Run it: \`spell-checker check …\`` bullet in the CLI-targets list:

```markdown
- Translate it: `spell-checker translate "<text>"` (or `pbpaste | spell-checker translate`) —
  **English → Russian only**, no autodetection. 1–2 words returns up to three meanings, each with a
  simple-English explanation and an example; 3+ words returns just the translation.
```

**`cli/README.md`** — add these two lines to the Usage block, matching the alignment of the `check` lines already there:

```
spell-checker translate <text>     Translate English → Russian
spell-checker translate            Read the text from stdin
```

and this worked example below the block — the `commit` example from the design note, so docs and design agree:

```
$ spell-checker translate commit
commit
  1. фиксация — saving your changes into the repository history
     "I commit my changes before lunch."
  2. обязательство — a promise to do something
     "This is a big commit of time."
  … more meanings exist
```

followed by:

```markdown
Direction is English → Russian only; there is no autodetection, so pasting Russian is undefined.
Three or more words returns the translation alone, which is what makes
`pbpaste | spell-checker translate | pbcopy` round-trip cleanly.
```

**`README.md`** — one sentence in the overview, no more; this is the front page, not the manual:

```markdown
The CLI also translates English into Russian — `spell-checker translate "<text>"` — returning up to
three meanings for a single word or short phrase, or just the translation for anything longer.
```

Do not restate the 2000-character limit in new prose; slice 1 already documented it in both files.

- [ ] **Step 2: Update the vault**

- `spell-checker-vault/Design/ad-hoc-translator.md`: change the Slice 2 heading to note it shipped, and correct anything execution changed — in particular, if the prompts you settled on differ from the ones quoted in the note, update the note to match the code. The vault is the source of truth; a prompt that exists only in Swift is a prompt nobody will find.
- `spell-checker-vault/Roadmap.md`, Phase 2.3: note that slices 1 and 2 have landed and slice 3 (the floating window) remains.

- [ ] **Step 3: Verify**

```bash
make test        # 41 tests, 0 failures
make build
grep -rn "translate" CLAUDE.md README.md cli/README.md | head
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md cli/README.md spell-checker-vault
git commit -m "docs: document spell-checker translate

Adds the command to both READMEs and CLAUDE.md, marks slice 2 shipped in the
design note, and updates Phase 2.3 in the roadmap. Any prompt wording that
changed during tuning is reflected back into the design note, so the prompts do
not live only in Swift.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Slice 2 Definition of Done

- `make test` passes at **41 tests** (23 before + 6 mode + 9 parse + 3 renderer).
- `make build` and `make app` both succeed — the app target must still compile after the `ClaudeCLI` extraction, even though nothing in it changed.
- `spell-checker check` still returns one verdict (the refactor's regression check).
- `spell-checker translate "commit"` returns up to three Russian meanings with readable simple-English explanations and examples.
- `spell-checker translate "<a sentence>"` returns one Russian sentence and nothing else, and pipes cleanly into `pbcopy`.
- Empty input and 2001 characters each exit 2, the latter instantly.
- No live document describes the CLI without `translate`.

## Not in this slice

The floating `NSPanel`, the `translating` icon state (`U+F05CA`), Hyper+⇧C, subprocess cancellation on dismissal, and the generation counter that stops a late reply rendering into a reopened panel. All of that is slice 3, which will consume the `onStart` hook this slice added to `ClaudeCLI.run`.

**One carry-forward for slice 3, from slice 1's ledger:** `IconState.allStates` is a hand-maintained array with a hardcoded count in its test. Adding `.translating` without extending it would leave the font-coverage test silently skipping the new glyph — and `U+F05CA` is above U+FFFF, exactly the class of codepoint that `Findings/nerd-font-codepoint-identity` says must be coverage-checked.
