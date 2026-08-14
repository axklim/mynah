# Configurable Language Pair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the translator's language pair a setting read from an XDG config file, and change the default from English → Russian to English → German.

**Architecture:** A new `MynahConfig` in `MynahCore` reads `key = value` lines from `$XDG_CONFIG_HOME/mynah/config.conf` (falling back to `~/.config/mynah/config.conf`) and yields a `LanguagePair` plus a model alias. The pair is injected into `ClaudeCLITranslator`'s initialiser and threaded into prompts built per-call; the `TextTranslator` protocol is untouched, so the documented backend-swap point (Decision 0006) stays as it is. The CLI loads the config per run; the menu-bar app loads it on every hotkey press through a `makeTranslator` closure, so an edit takes effect without a restart.

**Tech Stack:** Swift 6, SwiftPM (no new dependencies), XCTest, Foundation only in `MynahCore`.

**Spec:** `mynah-vault/Design/configurable-language-pair.md`

## Global Constraints

- **No new package dependency.** The parser is hand-written; `Package.swift` is not modified.
- **`MynahCore` imports no UI frameworks.** Foundation only, and each file declares its own `import Foundation`.
- **Renderers and mappings live in `MynahCore`/`MynahUI`, never in an executable target** — an executable target cannot be imported by the test bundle. Precedent: `TranslationResult+Terminal.swift`.
- **Defaults:** `source = English`, `target = German`, `model = sonnet`.
- **Config file name:** `config.conf`, under a `mynah/` directory.
- **`#` starts a comment only at the start of a line.** No trailing comments.
- **Keys are matched case-insensitively; values are not** (except the `source == target` comparison, which ignores case).
- **`mynah check` is not touched.** `ClaudeCLIEvaluator` and `CheckCoordinator` stay exactly as they are.
- **Language names are plain English words** passed into the prompt verbatim; there is no code table of languages and no ISO-code handling.
- Test suite baseline before this plan: **51 tests, 0 failures** (`make test` from the repo root).
- Commit titles are plain descriptive sentences — this repo takes **no ticket prefix** (`~/pet` exception).

---

### Task 1: The config parser

Pure text → `MynahConfig`, with no filesystem involved. This is the largest single artifact in the plan and the one carrying all the strictness rules.

**Files:**
- Create: `cli/Sources/MynahCore/MynahConfig.swift`
- Test: `cli/Tests/MynahCoreTests/MynahConfigParseTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `public struct LanguagePair: Sendable, Equatable` with `public let source: String`, `public let target: String`, `public init(source: String, target: String)`
  - `public struct MynahConfig: Sendable, Equatable` with `public let languages: LanguagePair`, `public let model: String`, `public init(languages: LanguagePair, model: String)`, `public static let \`default\`: MynahConfig`
  - `public struct ConfigError: Error, CustomStringConvertible, Equatable` with `public let path: String`, `public let line: Int?`, `public let reason: String`
  - `static func parse(_ text: String, path: String) throws -> MynahConfig` (internal, `@testable`)
  - `static let maxLanguageNameLength = 40` (internal)

- [ ] **Step 1: Write the failing tests**

Create `cli/Tests/MynahCoreTests/MynahConfigParseTests.swift`:

```swift
import XCTest
@testable import MynahCore

final class MynahConfigParseTests: XCTestCase {
    private let path = "/Users/someone/.config/mynah/config.conf"

    // MARK: - Defaults and happy paths

    func testEmptyTextIsAllDefaults() throws {
        let config = try MynahConfig.parse("", path: path)
        XCTAssertEqual(config, .default)
        XCTAssertEqual(config.languages.source, "English")
        XCTAssertEqual(config.languages.target, "German")
        XCTAssertEqual(config.model, "sonnet")
    }

    func testReadsBothLanguages() throws {
        let config = try MynahConfig.parse("source = German\ntarget = English", path: path)
        XCTAssertEqual(config.languages, LanguagePair(source: "German", target: "English"))
    }

    func testOnlyTargetSetKeepsTheDefaultSource() throws {
        let config = try MynahConfig.parse("target = Russian", path: path)
        XCTAssertEqual(config.languages, LanguagePair(source: "English", target: "Russian"))
        XCTAssertEqual(config.model, "sonnet")
    }

    func testCommentsAndBlankLinesAreIgnored() throws {
        let text = """
        # Language of the text you paste.
        source = English

           # indented comment

        target = German
        """
        XCTAssertEqual(try MynahConfig.parse(text, path: path), .default)
    }

    func testToleratesSpacingAroundEquals() throws {
        let config = try MynahConfig.parse("source=German\n   target   =   English   ", path: path)
        XCTAssertEqual(config.languages, LanguagePair(source: "German", target: "English"))
    }

    func testKeysAreCaseInsensitive() throws {
        let config = try MynahConfig.parse("TARGET = Russian\nModel = haiku", path: path)
        XCTAssertEqual(config.languages.target, "Russian")
        XCTAssertEqual(config.model, "haiku")
    }

    func testStripsOneMatchedPairOfSurroundingQuotes() throws {
        // Without this, the language is literally `"German"` and the model would
        // probably still translate into it — so the mistake would never surface.
        let config = try MynahConfig.parse("target = \"German\"", path: path)
        XCTAssertEqual(config.languages.target, "German")
    }

    func testKeepsInternalSpacesInValues() throws {
        let config = try MynahConfig.parse("target = Brazilian Portuguese", path: path)
        XCTAssertEqual(config.languages.target, "Brazilian Portuguese")
    }

    func testHashOnlyStartsACommentAtTheStartOfALine() throws {
        // No trailing comments: deciding what a `#` inside a value means is not
        // worth it for a file with three keys.
        let config = try MynahConfig.parse("target = German # my language", path: path)
        XCTAssertEqual(config.languages.target, "German # my language")
    }

    func testHandlesCRLFLineEndings() throws {
        let config = try MynahConfig.parse("source = German\r\ntarget = English\r\n", path: path)
        XCTAssertEqual(config.languages, LanguagePair(source: "German", target: "English"))
    }

    // MARK: - Strictness

    func testUnknownKeyIsAnErrorNamingTheLine() {
        XCTAssertThrowsError(try MynahConfig.parse("source = English\ntargt = Russian", path: path)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 2)
            XCTAssertEqual(error?.path, self.path)
            XCTAssertTrue(error?.reason.contains("targt") == true, "reason was \(error?.reason ?? "nil")")
        }
    }

    func testDuplicateKeyIsAnErrorNamingBothLines() {
        XCTAssertThrowsError(try MynahConfig.parse("target = German\ntarget = Russian", path: path)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 2)
            XCTAssertTrue(error?.reason.contains("line 1") == true, "reason was \(error?.reason ?? "nil")")
        }
    }

    func testLineWithoutEqualsIsAnError() {
        XCTAssertThrowsError(try MynahConfig.parse("target German", path: path)) {
            XCTAssertEqual(($0 as? ConfigError)?.line, 1)
        }
    }

    func testEmptyValueIsAnError() {
        XCTAssertThrowsError(try MynahConfig.parse("\ntarget =", path: path)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 2)
            XCTAssertTrue(error?.reason.contains("target") == true, "reason was \(error?.reason ?? "nil")")
        }
    }

    func testSourceEqualToTargetIsAnErrorIgnoringCase() {
        XCTAssertThrowsError(try MynahConfig.parse("source = English\ntarget = english", path: path)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 2)
            XCTAssertTrue(error?.reason.contains("english") == true, "reason was \(error?.reason ?? "nil")")
        }
    }

    func testDefaultSourceCollidingWithAnExplicitTargetIsAnError() {
        // `target = English` alone collides with the default source.
        XCTAssertThrowsError(try MynahConfig.parse("target = English", path: path))
    }

    func testOverlongLanguageNameIsAnError() {
        let long = String(repeating: "a", count: MynahConfig.maxLanguageNameLength + 1)
        XCTAssertThrowsError(try MynahConfig.parse("target = \(long)", path: path)) {
            XCTAssertEqual(($0 as? ConfigError)?.line, 1)
        }
    }

    func testModelIsNotValidatedAgainstAList() throws {
        // Model names change; a stale allowlist rejects a model that works.
        let config = try MynahConfig.parse("model = claude-opus-4-1", path: path)
        XCTAssertEqual(config.model, "claude-opus-4-1")
    }

    // MARK: - Error rendering

    func testErrorDescriptionNamesPathLineAndReason() {
        let error = ConfigError(path: path, line: 4, reason: "unknown key \"targt\"")
        XCTAssertEqual(error.description, "\(path) line 4: unknown key \"targt\"")
    }

    func testErrorDescriptionWithoutALineOmitsIt() {
        let error = ConfigError(path: path, line: nil, reason: "is not valid UTF-8")
        XCTAssertEqual(error.description, "\(path): is not valid UTF-8")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd cli && swift test --filter MynahConfigParseTests`
Expected: FAIL to compile — `cannot find 'MynahConfig' in scope`.

- [ ] **Step 3: Write the implementation**

Create `cli/Sources/MynahCore/MynahConfig.swift`:

```swift
import Foundation

/// Which language the developer pastes, and which one they want it in.
///
/// Plain English names ("German", "Brazilian Portuguese"), not ISO codes: the
/// only consumer is a natural-language prompt, which already understands them,
/// so there is no table to maintain and no language missing from it.
public struct LanguagePair: Sendable, Equatable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

/// Everything `~/.config/mynah/config.conf` can say.
///
/// The file is optional: its absence is the state of every fresh `brew install`
/// and simply means `.default`. A file that exists but cannot be read is an
/// error, because silently translating into the wrong language is the worst
/// possible answer to "your config is broken".
public struct MynahConfig: Sendable, Equatable {
    public let languages: LanguagePair
    /// Passed to `claude --model` verbatim. Deliberately not validated against a
    /// list of aliases: model names change, and a stale allowlist rejects a model
    /// that works.
    public let model: String

    public init(languages: LanguagePair, model: String) {
        self.languages = languages
        self.model = model
    }

    public static let `default` = MynahConfig(
        languages: LanguagePair(source: "English", target: "German"),
        model: "sonnet"
    )

    /// Longer than this is not a language name, it is a stray paste.
    static let maxLanguageNameLength = 40

    private static let knownKeys: Set<String> = ["source", "target", "model"]

    /// Parse `key = value` lines. Pure — the `path` is only ever used to build
    /// error messages, so the parser is testable without a filesystem.
    ///
    /// Strict on purpose: the whole failure mode of a small hand-edited file is a
    /// typo that quietly does nothing. Both products ship from one release asset
    /// (Decision 0011), so an older binary can never meet a newer config — there
    /// is no forward-compatibility argument for ignoring unknown keys.
    static func parse(_ text: String, path: String) throws -> MynahConfig {
        var values: [String: String] = [:]
        var lineOf: [String: Int] = [:]

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for (index, rawLine) in normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).enumerated() {
            let number = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // `#` comments only at the start of a line — no trailing comments, so
            // there is never a question about what a `#` inside a value means.
            if line.isEmpty || line.hasPrefix("#") { continue }

            guard let equals = line.firstIndex(of: "=") else {
                throw ConfigError(
                    path: path,
                    line: number,
                    reason: "expected `key = value`, found \(line.debugDescription)"
                )
            }

            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = unquoted(
                String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            )

            guard knownKeys.contains(key) else {
                throw ConfigError(
                    path: path,
                    line: number,
                    reason: "unknown key \(key.debugDescription) — expected source, target or model"
                )
            }
            guard !value.isEmpty else {
                throw ConfigError(path: path, line: number, reason: "\(key) has no value")
            }
            if let first = lineOf[key] {
                throw ConfigError(
                    path: path,
                    line: number,
                    reason: "\(key) is already set on line \(first)"
                )
            }

            values[key] = value
            lineOf[key] = number
        }

        let source = values["source"] ?? Self.default.languages.source
        let target = values["target"] ?? Self.default.languages.target

        for (key, value) in [("source", source), ("target", target)]
        where value.count > maxLanguageNameLength {
            throw ConfigError(
                path: path,
                line: lineOf[key],
                reason: "\(key) is \(value.count) characters — that is not a language name"
            )
        }

        guard source.lowercased() != target.lowercased() else {
            throw ConfigError(
                path: path,
                line: lineOf["target"] ?? lineOf["source"],
                reason: "source and target are both \(target.debugDescription) — "
                    + "there would be nothing to translate"
            )
        }

        return MynahConfig(
            languages: LanguagePair(source: source, target: target),
            model: values["model"] ?? Self.default.model
        )
    }

    /// Drop one matched pair of surrounding double quotes. Without this,
    /// `target = "German"` yields a language literally named `"German"`, which the
    /// model would probably still translate into — so the mistake would be
    /// invisible rather than wrong.
    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }
}

/// A config file that exists but cannot be used, phrased so both products can
/// print it unchanged: the CLI to stderr, the app into the translation panel.
public struct ConfigError: Error, CustomStringConvertible, Equatable {
    public let path: String
    /// nil when the problem is the file as a whole rather than one line.
    public let line: Int?
    public let reason: String

    public init(path: String, line: Int?, reason: String) {
        self.path = path
        self.line = line
        self.reason = reason
    }

    public var description: String {
        guard let line else { return "\(path): \(reason)" }
        return "\(path) line \(line): \(reason)"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd cli && swift test --filter MynahConfigParseTests`
Expected: PASS, 20 tests.

- [ ] **Step 5: Run the whole suite**

Run: `make test`
Expected: PASS, 71 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add cli/Sources/MynahCore/MynahConfig.swift cli/Tests/MynahCoreTests/MynahConfigParseTests.swift
git commit -m "Add the mynah config parser"
```

---

### Task 2: Path resolution, loading, and `mynah config` rendering

Everything that touches the filesystem, plus the round-trip that makes `mynah config > config.conf` a safe init step.

**Files:**
- Modify: `cli/Sources/MynahCore/MynahConfig.swift` (append the loading API)
- Create: `cli/Sources/MynahCore/MynahConfig+Terminal.swift`
- Test: `cli/Tests/MynahCoreTests/MynahConfigFileTests.swift`

**Interfaces:**
- Consumes: `MynahConfig`, `LanguagePair`, `ConfigError`, `MynahConfig.parse(_:path:)` from Task 1.
- Produces:
  - `public static func path(environment: [String: String], home: URL) -> URL`
  - `public static func load(environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = URL(fileURLWithPath: NSHomeDirectory())) throws -> MynahConfig`
  - `public func configFileText(path: String, exists: Bool) -> String`

- [ ] **Step 1: Write the failing tests**

Create `cli/Tests/MynahCoreTests/MynahConfigFileTests.swift`:

```swift
import XCTest
@testable import MynahCore

final class MynahConfigFileTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/someone")

    /// A unique empty directory per test, removed in tearDown.
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("mynah-config-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        scratch = nil
    }

    /// Write `text` to `<scratch>/.config/mynah/config.conf` and return a home
    /// directory pointing at the scratch dir.
    private func writeConfig(_ text: String) throws -> URL {
        let dir = scratch.appendingPathComponent(".config/mynah", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: dir.appendingPathComponent("config.conf"))
        return scratch
    }

    // MARK: - Path resolution

    func testUsesXDGConfigHomeWhenAbsolute() {
        let url = MynahConfig.path(environment: ["XDG_CONFIG_HOME": "/opt/cfg"], home: home)
        XCTAssertEqual(url.path, "/opt/cfg/mynah/config.conf")
    }

    func testFallsBackWhenXDGConfigHomeIsRelative() {
        // A relative XDG_CONFIG_HOME is invalid per the spec, and resolving it
        // against the current directory would mean the app reads its own private
        // scratch dir.
        let url = MynahConfig.path(environment: ["XDG_CONFIG_HOME": "cfg"], home: home)
        XCTAssertEqual(url.path, "/Users/someone/.config/mynah/config.conf")
    }

    func testFallsBackWhenXDGConfigHomeIsEmpty() {
        let url = MynahConfig.path(environment: ["XDG_CONFIG_HOME": ""], home: home)
        XCTAssertEqual(url.path, "/Users/someone/.config/mynah/config.conf")
    }

    func testFallsBackWhenXDGConfigHomeIsUnset() {
        let url = MynahConfig.path(environment: [:], home: home)
        XCTAssertEqual(url.path, "/Users/someone/.config/mynah/config.conf")
    }

    // MARK: - Loading

    func testMissingFileYieldsDefaults() throws {
        let config = try MynahConfig.load(environment: [:], home: scratch)
        XCTAssertEqual(config, .default)
    }

    func testReadsAFileFromDisk() throws {
        let home = try writeConfig("target = Russian\nmodel = haiku\n")
        let config = try MynahConfig.load(environment: [:], home: home)
        XCTAssertEqual(config.languages, LanguagePair(source: "English", target: "Russian"))
        XCTAssertEqual(config.model, "haiku")
    }

    func testXDGConfigHomeWins() throws {
        let dir = scratch.appendingPathComponent("xdg/mynah", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("target = Russian".utf8).write(to: dir.appendingPathComponent("config.conf"))
        _ = try writeConfig("target = French")

        let config = try MynahConfig.load(
            environment: ["XDG_CONFIG_HOME": scratch.appendingPathComponent("xdg").path],
            home: scratch
        )
        XCTAssertEqual(config.languages.target, "Russian")
    }

    func testParseErrorsCarryTheRealPath() throws {
        let home = try writeConfig("targt = Russian")
        XCTAssertThrowsError(try MynahConfig.load(environment: [:], home: home)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 1)
            XCTAssertTrue(
                error?.path.hasSuffix(".config/mynah/config.conf") == true,
                "path was \(error?.path ?? "nil")"
            )
        }
    }

    func testAPathThatIsADirectoryIsAnError() throws {
        // `fileExists` says yes for a directory, so this is the branch where the
        // file is present but unreadable — the one case that must not fall back
        // to defaults.
        try FileManager.default.createDirectory(
            at: scratch.appendingPathComponent(".config/mynah/config.conf", isDirectory: true),
            withIntermediateDirectories: true
        )
        XCTAssertThrowsError(try MynahConfig.load(environment: [:], home: scratch)) {
            let error = $0 as? ConfigError
            XCTAssertNil(error?.line)
            XCTAssertTrue(
                error?.reason.contains("could not be read") == true,
                "reason was \(error?.reason ?? "nil")"
            )
        }
    }

    func testFileThatIsNotUTF8IsAnError() throws {
        let dir = scratch.appendingPathComponent(".config/mynah", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 0xFF is not valid UTF-8 in any position.
        try Data([0x74, 0x61, 0xFF]).write(to: dir.appendingPathComponent("config.conf"))

        XCTAssertThrowsError(try MynahConfig.load(environment: [:], home: scratch)) {
            let error = $0 as? ConfigError
            XCTAssertNil(error?.line)
            XCTAssertTrue(error?.reason.contains("UTF-8") == true, "reason was \(error?.reason ?? "nil")")
        }
    }

    // MARK: - `mynah config` output

    func testConfigFileTextNamesThePath() {
        let text = MynahConfig.default.configFileText(path: "/tmp/config.conf", exists: true)
        XCTAssertTrue(text.hasPrefix("# /tmp/config.conf\n"), "text was \(text)")
        XCTAssertFalse(text.contains("not found"))
    }

    func testConfigFileTextSaysWhenTheFileIsMissing() {
        let text = MynahConfig.default.configFileText(path: "/tmp/config.conf", exists: false)
        XCTAssertTrue(text.contains("not found"), "text was \(text)")
    }

    func testConfigFileTextRoundTrips() throws {
        // `mynah config > ~/.config/mynah/config.conf` must produce a file that
        // parses back to exactly the same settings.
        let config = MynahConfig(
            languages: LanguagePair(source: "German", target: "Brazilian Portuguese"),
            model: "haiku"
        )
        let text = config.configFileText(path: "/tmp/config.conf", exists: false)
        XCTAssertEqual(try MynahConfig.parse(text, path: "/tmp/config.conf"), config)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd cli && swift test --filter MynahConfigFileTests`
Expected: FAIL to compile — `type 'MynahConfig' has no member 'path'`.

- [ ] **Step 3: Append the loading API to `MynahConfig.swift`**

Add inside the `MynahConfig` struct, after `parse(_:path:)`:

```swift
    /// `$XDG_CONFIG_HOME/mynah/config.conf`, else `~/.config/mynah/config.conf`.
    ///
    /// The variable is honoured only when it is an **absolute** path, per the XDG
    /// base directory spec — a relative value is invalid, and resolving it against
    /// the current directory would point the app at its own empty scratch dir
    /// (Finding: gui-claude-subprocess-tcc-prompt).
    ///
    /// Environment and home come in as parameters so tests never read the
    /// developer's real `$HOME`.
    public static func path(environment: [String: String], home: URL) -> URL {
        if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            return URL(fileURLWithPath: xdg).appendingPathComponent("mynah/config.conf")
        }
        return home.appendingPathComponent(".config/mynah/config.conf")
    }

    /// Read and parse the config, or return `.default` when there is no file.
    ///
    /// "Absent" is a deliberate state — every fresh `brew install` is in it.
    /// "Present but unreadable" is a problem the user wants told about, so it
    /// throws rather than falling back.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) throws -> MynahConfig {
        let url = path(environment: environment, home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return .default }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError(
                path: url.path,
                line: nil,
                reason: "could not be read (\(error.localizedDescription))"
            )
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigError(path: url.path, line: nil, reason: "is not valid UTF-8")
        }
        return try parse(text, path: url.path)
    }
```

- [ ] **Step 4: Write the `mynah config` renderer**

Create `cli/Sources/MynahCore/MynahConfig+Terminal.swift`:

```swift
public extension MynahConfig {
    /// Render the effective settings **as a valid config file**, so
    /// `mynah config > ~/.config/mynah/config.conf` is the init step and the
    /// output doubles as documentation of where the file lives.
    ///
    /// Lives in Core rather than in the CLI target because an executable target
    /// cannot be imported by the test bundle — same reason as
    /// `TranslationResult.terminalText(source:)`.
    func configFileText(path: String, exists: Bool) -> String {
        """
        # \(path)\(exists ? "" : " (not found — showing defaults)")
        source = \(languages.source)
        target = \(languages.target)
        model = \(model)
        """
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd cli && swift test --filter MynahConfigFileTests`
Expected: PASS, 13 tests.

- [ ] **Step 6: Run the whole suite**

Run: `make test`
Expected: PASS, 84 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add cli/Sources/MynahCore/MynahConfig.swift cli/Sources/MynahCore/MynahConfig+Terminal.swift cli/Tests/MynahCoreTests/MynahConfigFileTests.swift
git commit -m "Read the mynah config from the XDG config path"
```

---

### Task 3: Pair-aware prompts and translator

The prompts stop being constants and become functions of the pair. `ClaudeCLITranslator` carries the pair.

**Files:**
- Create: `cli/Sources/MynahCore/TranslationPrompts.swift`
- Modify: `cli/Sources/MynahCore/TextTranslator.swift` (delete the two prompt constants at the bottom, lines 76-103)
- Modify: `cli/Sources/MynahCore/ClaudeCLITranslator.swift`
- Test: `cli/Tests/MynahCoreTests/TranslationPromptsTests.swift`

**Interfaces:**
- Consumes: `LanguagePair`, `MynahConfig` from Task 1.
- Produces:
  - `enum TranslationPrompts` (internal) with `static func text(_ pair: LanguagePair) -> String` and `static func word(_ pair: LanguagePair) -> String`
  - `ClaudeCLITranslator.init(languages: LanguagePair, model: String = MynahConfig.default.model)`
  - `ClaudeCLITranslator.init(_ config: MynahConfig)`
  - `public var languages: LanguagePair` on `ClaudeCLITranslator`

Note: `languages` has **no default value** on the initialiser. Every call site must say which pair it means, so a forgotten config read is a compile error rather than a silent German translation.

- [ ] **Step 1: Write the failing tests**

Create `cli/Tests/MynahCoreTests/TranslationPromptsTests.swift`:

```swift
import XCTest
@testable import MynahCore

final class TranslationPromptsTests: XCTestCase {
    private let enToDe = LanguagePair(source: "English", target: "German")
    private let deToEn = LanguagePair(source: "German", target: "English")

    func testTextPromptNamesBothLanguagesInTheRightRoles() {
        let prompt = TranslationPrompts.text(enToDe)
        XCTAssertTrue(prompt.contains("Translate the following English text into German"), prompt)
        XCTAssertTrue(prompt.contains("ONLY the German translation"), prompt)
    }

    func testTextPromptFlipsWithThePair() {
        let prompt = TranslationPrompts.text(deToEn)
        XCTAssertTrue(prompt.contains("Translate the following German text into English"), prompt)
    }

    func testWordPromptAsksForTranslationsInTheTarget() {
        let prompt = TranslationPrompts.word(enToDe)
        XCTAssertTrue(prompt.contains("the German translation"), prompt)
    }

    func testWordPromptAsksForExplanationsInTheSource() {
        // Locked decision: explanation and example follow the SOURCE language, so
        // the default pair keeps today's simple-English teaching material.
        let prompt = TranslationPrompts.word(enToDe)
        XCTAssertTrue(prompt.contains("in simple English"), prompt)
        XCTAssertTrue(prompt.contains("natural English sentence"), prompt)
    }

    func testWordPromptExplanationsFlipWithThePair() {
        let prompt = TranslationPrompts.word(deToEn)
        XCTAssertTrue(prompt.contains("in simple German"), prompt)
        XCTAssertTrue(prompt.contains("natural German sentence"), prompt)
        XCTAssertTrue(prompt.contains("the English translation"), prompt)
    }

    func testWordPromptNoLongerAssumesTheReaderIsRussianSpeaking() {
        // With the pair configurable, the user's native language is not derivable
        // from it — `de→en` says nothing about who is reading.
        XCTAssertFalse(TranslationPrompts.word(enToDe).contains("Russian"))
    }

    func testWordPromptStillPinsTheJSONShape() {
        let prompt = TranslationPrompts.word(enToDe)
        XCTAssertTrue(prompt.contains("\"hasMore\""), prompt)
        XCTAssertTrue(prompt.contains("minified JSON"), prompt)
    }

    func testTranslatorTakesItsPairFromAConfig() {
        let config = MynahConfig(
            languages: LanguagePair(source: "German", target: "English"),
            model: "haiku"
        )
        let translator = ClaudeCLITranslator(config)
        XCTAssertEqual(translator.languages, config.languages)
        XCTAssertEqual(translator.model, "haiku")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd cli && swift test --filter TranslationPromptsTests`
Expected: FAIL to compile — `cannot find 'TranslationPrompts' in scope`.

- [ ] **Step 3: Create the prompt builders**

Create `cli/Sources/MynahCore/TranslationPrompts.swift`:

```swift
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
```

- [ ] **Step 4: Delete the old constants**

In `cli/Sources/MynahCore/TextTranslator.swift`, delete everything from the comment `/// Text mode: the reply is used verbatim…` (line 76) to the end of the file — both `textTranslationPrompt` and `wordTranslationPrompt`.

In the same file, update the doc comments that hard-code the direction:
- Line 4: `/// sentence. Anything longer is prose they want to read in Russian.` → `/// sentence. Anything longer is prose they want to read in the target language.`
- Line 19: `/// One Russian meaning of an English word, with teaching material.` → `/// One target-language meaning of a source-language word, with teaching material.`
- Line 25-27: change the trailing comments to `// target language`, `// simple source language`, `// simple source language`
- Line 41: `/// Just the Russian.` → `/// Just the translation.`
- Line 54: `/// Translate English into Russian. The shape of the result follows` → `/// Translate from the configured source language into the target. The shape of the result follows`

- [ ] **Step 5: Thread the pair through the translator**

In `cli/Sources/MynahCore/ClaudeCLITranslator.swift`, replace the header and initialiser (lines 1-16) with:

```swift
import Foundation

/// Translates between the configured language pair by asking Claude through
/// `ClaudeCLI`.
public struct ClaudeCLITranslator: TextTranslator {
    /// Which way round to translate. No default: every call site must say which
    /// pair it means, so a forgotten config read is a compile error rather than a
    /// silent translation into the wrong language.
    public var languages: LanguagePair

    /// Model alias passed to `claude --model`. Sonnet by default, matching the
    /// evaluator: Haiku under-performed on nuance in this project. Configurable,
    /// so trying Haiku for text mode is a config edit.
    public var model: String

    /// Word mode never shows more than this many meanings; the rest are reported
    /// by `hasMore`.
    static let maxMeanings = 3

    public init(languages: LanguagePair, model: String = MynahConfig.default.model) {
        self.languages = languages
        self.model = model
    }

    /// The everyday initialiser: `ClaudeCLITranslator(try MynahConfig.load())`.
    public init(_ config: MynahConfig) {
        self.init(languages: config.languages, model: config.model)
    }
```

Then in `translate(_:onStart:)`, replace the two prompt references:
- `prompt: textTranslationPrompt + "\n\n" + text` → `prompt: TranslationPrompts.text(languages) + "\n\n" + text`
- `prompt: wordTranslationPrompt + "\n\n" + text` → `prompt: TranslationPrompts.word(languages) + "\n\n" + text`

- [ ] **Step 6: Keep the two call sites compiling**

Removing the no-argument initialiser breaks `main.swift` and `AppDelegate.swift`. SwiftPM builds
every target for `swift test`, so leaving them broken would run **zero** tests — verified. Update
both to a compiling form now; Tasks 4 and 5 refine them.

In `cli/Sources/Mynah/main.swift`, inside `case "translate":`, move the construction into the
existing `do` block so the `try` has somewhere to go:

```swift
    do {
        let translator: TextTranslator = ClaudeCLITranslator(try MynahConfig.load())
        emit(try translator.translate(source).terminalText(source: source), to: .standardOutput)
    } catch {
        fail("error: \(error)", code: 1)
    }
```

In `cli/Sources/MynahBar/AppDelegate.swift`:

```swift
        translateCoordinator = TranslateCoordinator(
            status: status,
            // Replaced in the next task by a per-press config read.
            translator: ClaudeCLITranslator(MynahConfig.default)
        )
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd cli && swift test --filter TranslationPromptsTests`
Expected: PASS, 8 tests.

- [ ] **Step 8: Run the whole suite**

Run: `make test`
Expected: PASS, 92 tests, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add cli/Sources/MynahCore/TranslationPrompts.swift cli/Sources/MynahCore/TextTranslator.swift cli/Sources/MynahCore/ClaudeCLITranslator.swift cli/Sources/Mynah/main.swift cli/Sources/MynahBar/AppDelegate.swift cli/Tests/MynahCoreTests/TranslationPromptsTests.swift
git commit -m "Build the translation prompts from the configured language pair"
```

---

### Task 4: The CLI reads the config, and `mynah config`

Completes slice 1: everything is verifiable in a terminal after this task.

**Files:**
- Modify: `cli/Sources/Mynah/main.swift`

**Interfaces:**
- Consumes: `MynahConfig.load()`, `MynahConfig.path(environment:home:)`, `configFileText(path:exists:)`, `ClaudeCLITranslator(_:)`.
- Produces: no new API — this is the CLI surface.

- [ ] **Step 1: Update the usage string**

Replace the `usage` constant at the top of `cli/Sources/Mynah/main.swift`:

```swift
let usage = """
mynah — evaluate whether a message reads clearly.

USAGE:
  mynah check <text>       Evaluate text; prints one verdict: 🔴 / 🟡 / 🟢
  mynah check              Read the text from stdin (e.g. pbpaste | mynah check)
  mynah translate <text>   Translate text between the configured languages
  mynah translate          Read the text from stdin
  mynah config             Print the effective config and where it lives
  mynah --help             Show this help
  mynah --version          Print the version

Translation defaults to English → German. Change it in the config file; run
`mynah config` to see the path and the current settings.

Input over 2000 characters is rejected as a likely misclick.
"""
```

- [ ] **Step 2: Load the config in `translate`**

Replace the `case "translate":` block:

```swift
case "translate":
    // Load before reading the input: a broken config should be reported at once,
    // not after blocking on stdin.
    let config: MynahConfig
    do {
        config = try MynahConfig.load()
    } catch {
        fail("error: \(error)", code: 2)
    }

    let source = requireInput(
        Array(args.dropFirst()),
        usage: "usage: mynah translate <text>   (or pipe text via stdin)"
    )

    let translator: TextTranslator = ClaudeCLITranslator(config)
    do {
        emit(try translator.translate(source).terminalText(source: source), to: .standardOutput)
    } catch {
        fail("error: \(error)", code: 1)
    }
```

- [ ] **Step 3: Add the `config` subcommand**

Insert a new case after `case "translate":`'s block and before `case .none:`:

```swift
case "config":
    let configPath = MynahConfig.path(
        environment: ProcessInfo.processInfo.environment,
        home: URL(fileURLWithPath: NSHomeDirectory())
    )
    let exists = FileManager.default.fileExists(atPath: configPath.path)

    let effective: MynahConfig
    do {
        effective = try MynahConfig.load()
    } catch {
        fail("error: \(error)", code: 2)
    }
    emit(
        effective.configFileText(path: configPath.path, exists: exists),
        to: .standardOutput
    )
```

- [ ] **Step 4: Build and check the whole suite compiles again**

Run: `make test`
Expected: PASS, 92 tests, 0 failures. (Task 3 already made both call sites compile; `AppDelegate` is still on `MynahConfig.default` until Task 5.)

- [ ] **Step 5: Verify the default pair by hand**

Run:
```bash
cd cli
swift run mynah config
swift run mynah translate "Could you take a look at my PR when you have a moment?"
```
Expected: `mynah config` prints the path with `(not found — showing defaults)` and `target = German`; the translation comes back in **German**.

- [ ] **Step 6: Verify an edited config by hand**

Run:
```bash
mkdir -p ~/.config/mynah
cd cli && swift run mynah config > ~/.config/mynah/config.conf
sed -i '' 's/^target = German/target = Russian/' ~/.config/mynah/config.conf
swift run mynah config
swift run mynah translate "Could you take a look at my PR when you have a moment?"
swift run mynah translate commit
```
Expected: `config` no longer says "not found"; the sentence comes back in **Russian without a rebuild**; `commit` returns up to 3 Russian meanings with **simple-English** explanations and examples.

- [ ] **Step 7: Verify the error paths by hand**

Run:
```bash
printf 'targt = Russian\n' > ~/.config/mynah/config.conf
cd cli && swift run mynah translate "hello there friend"; echo "exit=$?"
swift run mynah config; echo "exit=$?"
swift run mynah check "hello there friend"; echo "exit=$?"
```
Expected: the first two print `error: …/config.conf line 1: unknown key "targt" …` and `exit=2`; `mynah check` still prints a verdict and `exit=0`, proving the config never touches the checker.

- [ ] **Step 8: Restore a working config**

Run: `cd cli && swift run mynah config > /dev/null 2>&1; printf '# ~/.config/mynah/config.conf\nsource = English\ntarget = German\n' > ~/.config/mynah/config.conf`

- [ ] **Step 9: Commit**

```bash
git add cli/Sources/Mynah/main.swift
git commit -m "Read the language pair from the config in the CLI"
```

---

### Task 5: The menu-bar app re-reads the config on every press

Slice 2. One injection point swapped for another.

**Files:**
- Modify: `cli/Sources/MynahUI/TranslationViewState.swift`
- Modify: `cli/Sources/MynahBar/TranslateCoordinator.swift:13-32` and `:34-69`
- Modify: `cli/Sources/MynahBar/AppDelegate.swift:14-17`
- Test: `cli/Tests/MynahCoreTests/TranslationViewStateTests.swift` (append)

**Interfaces:**
- Consumes: `MynahConfig.load()`, `ClaudeCLITranslator(_:)`, `ConfigError`.
- Produces: `TranslationViewState.configFailure(_ error: Error) -> TranslationViewState`; `TranslateCoordinator.init(status:makeTranslator:)`.

- [ ] **Step 1: Write the failing test**

Append to `cli/Tests/MynahCoreTests/TranslationViewStateTests.swift`, inside the existing class:

```swift
    func testConfigFailureNamesTheFileAndTheProblem() {
        let error = ConfigError(
            path: "/Users/someone/.config/mynah/config.conf",
            line: 4,
            reason: "unknown key \"targt\""
        )
        guard case .failed(let message) = TranslationViewState.configFailure(error) else {
            return XCTFail("expected .failed")
        }
        // The user has to go and edit the file, so the path has to be in the window.
        XCTAssertTrue(message.contains("config.conf"), message)
        XCTAssertTrue(message.contains("line 4"), message)
        XCTAssertTrue(message.contains("targt"), message)
        // Not the claude-failure wording: that would be a lie.
        XCTAssertFalse(message.contains("Couldn't reach claude"), message)
    }
```

No import change is needed: the file already has `import MynahCore` (line 2), and `ConfigError` is public.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd cli && swift test --filter TranslationViewStateTests`
Expected: FAIL to compile — `type 'TranslationViewState' has no member 'configFailure'`.

- [ ] **Step 3: Add the view state**

In `cli/Sources/MynahUI/TranslationViewState.swift`, add after `failure(_:)`:

```swift
    /// Map a config problem onto the view. Deliberately separate from
    /// `failure(_:)`: "Couldn't reach claude" would be a lie, and the fix is in a
    /// file whose path therefore has to be on screen.
    public static func configFailure(_ error: Error) -> TranslationViewState {
        .failed("Your mynah config has a problem — \(error)")
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd cli && swift test --filter TranslationViewStateTests`
Expected: PASS, 7 tests (6 existing plus this one).

- [ ] **Step 5: Swap the coordinator's injection point**

In `cli/Sources/MynahBar/TranslateCoordinator.swift`, replace the stored property and initialiser:

```swift
    private let status: StatusItemController
    /// Built fresh for every run rather than stored, so the config file is re-read
    /// on each press: edit it, press the hotkey, done — no restart, no "Reload
    /// config" menu item. A throwing closure also gives a broken config somewhere
    /// to land (the panel) instead of crashing the app at launch.
    private let makeTranslator: () throws -> any TextTranslator
    private let panel: TranslationPanel

    private var isTranslating = false
    private var handle: TranslationHandle?

    /// Bumped on every run. A reply from run *n* is dropped once run *n + 1* has
    /// started, so a slow translation cannot paint over a newer one — or over a
    /// panel the user has already dismissed and reopened.
    private var generation = 0

    init(status: StatusItemController, makeTranslator: @escaping () throws -> any TextTranslator) {
        self.status = status
        self.makeTranslator = makeTranslator
        var dismissed: (() -> Void)?
        self.panel = TranslationPanel { dismissed?() }
        dismissed = { [weak self] in self?.handleDismissal() }
    }
```

- [ ] **Step 6: Build the translator inside `runTranslate`**

In the same file, in `runTranslate()`, insert after the input-guard `switch` and before `generation += 1`:

```swift
        // After the input guard, not before: an empty clipboard is the common
        // mistake and deserves the plainer message. (The CLI loads first only
        // because its input can block on stdin.)
        let translator: any TextTranslator
        do {
            translator = try makeTranslator()
        } catch {
            panel.show(TranslationViewState.configFailure(error))
            return
        }
```

Then delete the now-redundant `let translator = self.translator` line that sits just before `Task {`.

- [ ] **Step 7: Wire it up in `AppDelegate`**

In `cli/Sources/MynahBar/AppDelegate.swift`, replace the `translateCoordinator` construction:

```swift
        translateCoordinator = TranslateCoordinator(status: status) {
            ClaudeCLITranslator(try MynahConfig.load())
        }
```

- [ ] **Step 8: Run the whole suite**

Run: `make test`
Expected: PASS, 93 tests, 0 failures, and every target builds again.

- [ ] **Step 9: Verify in the real app**

Run: `make run-app`

Then, with `~/.config/mynah/config.conf` holding the default `English` → `German`:
1. Copy `Could you take a look at my PR when you have a moment?`, press **⌃⌥⌘⇧C** → German in the panel.
2. Without quitting the app, `sed -i '' 's/^target = German/target = Russian/' ~/.config/mynah/config.conf`, press the hotkey again → **Russian**, no restart.
3. Copy `commit`, press the hotkey → up to 3 meanings with simple-English explanations.
4. `printf 'targt = Russian\n' > ~/.config/mynah/config.conf`, press the hotkey → the panel reads "Your mynah config has a problem — …line 1: unknown key…"; press **⌃⌥⌘C** → the checker still returns a verdict in the icon.
5. Quit and relaunch with the broken config still in place → the app still launches and the menu still works.
6. Restore `target = German`.

- [ ] **Step 10: Commit**

```bash
git add cli/Sources/MynahUI/TranslationViewState.swift cli/Sources/MynahBar/TranslateCoordinator.swift cli/Sources/MynahBar/AppDelegate.swift cli/Tests/MynahCoreTests/TranslationViewStateTests.swift
git commit -m "Re-read the config on every translate hotkey press"
```

---

### Task 6: Documentation and vault

Every doc that names "English → Russian", plus the two vault notes the design promised.

**Files:**
- Modify: `CLAUDE.md`, `README.md:18,38,56`, `cli/README.md:52-53,57,70,90-91`
- Create: `mynah-vault/Decisions/0012-xdg-config-language-pair.md`
- Create: `mynah-vault/Findings/xdg-config-invisible-to-the-app.md`
- Modify: `mynah-vault/Home.md`, `mynah-vault/Roadmap.md`, `mynah-vault/Design/ad-hoc-translator.md`, `mynah-vault/Ideas/inbox.md`, `mynah-vault/Design/configurable-language-pair.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Update `CLAUDE.md`**

Three edits:
1. In the tech-decisions table, add a row after `Storage`: `| Config | XDG file at \`$XDG_CONFIG_HOME/mynah/config.conf\` (fallback \`~/.config/mynah/config.conf\`); \`key = value\`, hand-parsed, no dependency (Decision 0012) |`
2. In the CLI target list, add: `- \`mynah config\` — print the effective config and where it lives. \`mkdir -p ~/.config/mynah && mynah config > ~/.config/mynah/config.conf\` writes a starter file.`
3. Replace both "English → Russian only, no autodetection" passages (the `mynah translate` bullet and the ⌃⌥⌘⇧C paragraph) with the configured pair, defaulting to **English → German**, changed by editing the config file, re-read on every press.

- [ ] **Step 2: Update `README.md` and `cli/README.md`**

Replace every "English into Russian" / "English → Russian" with the configured pair and the English → German default. In `cli/README.md`, add a `## Configuration` section after the `translate` section:

```markdown
## Configuration

Translation reads `$XDG_CONFIG_HOME/mynah/config.conf`, falling back to
`~/.config/mynah/config.conf`. Without a file, the pair is **English → German**.

```
# Language of the text you paste.
source = English

# Language you want it in.
target = German

# Model passed to `claude --model`.
# model = sonnet
```

`mynah config` prints the effective settings as a valid config file, so
`mkdir -p ~/.config/mynah && mynah config > ~/.config/mynah/config.conf` writes a
starter. Languages are plain English names — `Brazilian Portuguese` works.

The file is parsed strictly: an unknown key, a duplicate key, an empty value, or
`source` equal to `target` is an error naming the line. `#` starts a comment only
at the start of a line. `mynah check` does not read this file.

The menu-bar app re-reads it on every hotkey press, so an edit takes effect
without restarting. One caveat: a Finder- or `launchd`-launched app inherits no
shell environment, so `$XDG_CONFIG_HOME` is invisible to `Mynah.app` even when
the CLI in your terminal can see it. They agree whenever it is unset.
```

- [ ] **Step 3: Write the Decision note**

Create `mynah-vault/Decisions/0012-xdg-config-language-pair.md`, following the format of `0011-homebrew-tap-prebuilt.md`: status accepted, dated 2026-08-14; context (the direction was hard-wired in two prompt constants and the developer now wants German); the decision (one configurable pair, XDG `key = value` file, plain language names, default English → German, strict parsing, pair injected into the translator's initialiser so `TextTranslator` is untouched); consequences (first config file in the project, `mynah check` still English-only, the app/CLI `$XDG_CONFIG_HOME` divergence); and links to `[[configurable-language-pair]]`, `[[ad-hoc-translator]]`, `[[0006-polish-backend-claude-cli]]`.

- [ ] **Step 4: Confirm the divergence the Finding is about**

Run:
```bash
mkdir -p /tmp/mynah-xdg/mynah
printf 'target = French\n' > /tmp/mynah-xdg/mynah/config.conf
cd cli && XDG_CONFIG_HOME=/tmp/mynah-xdg swift run mynah config
```
Expected: the CLI reports `/tmp/mynah-xdg/mynah/config.conf` and `target = French`. Now press **⌃⌥⌘⇧C** in the already-running `Mynah.app` with a sentence on the clipboard: it translates to **German** (or whatever `~/.config/mynah/config.conf` says), *not* French — the app never saw the variable. Clean up with `rm -rf /tmp/mynah-xdg`.

- [ ] **Step 5: Write the Finding note**

Create `mynah-vault/Findings/xdg-config-invisible-to-the-app.md`: a Finder- or `launchd`-launched `.app` inherits no shell environment, so `$XDG_CONFIG_HOME` set in a shell rc is visible to `mynah` and invisible to `Mynah.app`, which then reads `~/.config/mynah/config.conf`. Same root cause as `[[gui-claude-subprocess-tcc-prompt]]`'s `PATH` problem. They agree whenever the variable is unset, which is the normal case. Rejected fixes: ignoring the variable entirely (breaks the XDG contract for CLI users), and reading the shell rc (fragile and surprising). Accepted: document it.

- [ ] **Step 6: Update the vault index and roadmap**

1. `mynah-vault/Home.md` — add `[[configurable-language-pair]]` to the Design list, `[[0012-xdg-config-language-pair]]` to Decisions, and `[[xdg-config-invisible-to-the-app]]` to Findings.
2. `mynah-vault/Roadmap.md` — add after Phase 2.3:

```markdown
- [x] **Phase 2.4 — Configurable language pair** *(design: [[configurable-language-pair]])*
  The translator's direction becomes a setting in an XDG config file
  (`~/.config/mynah/config.conf`), and the default changes from English → Russian to
  **English → German**. One active pair, both sides configurable; word-mode explanations
  follow the source language. Adds `mynah config` and the project's first config file
  ([[0012-xdg-config-language-pair]]). `mynah check` stays English-only.
```

3. `mynah-vault/Design/ad-hoc-translator.md` — in the locked-decisions table, change the Direction row to note it is superseded by `[[configurable-language-pair]]`, keeping the original text so the history reads.
4. `mynah-vault/Ideas/inbox.md` — the "Ru → En autodetection" item gains a pointer: the direction is now configurable per `[[configurable-language-pair]]`; what is left of this idea is *auto*detection, not configuration. The "Try Haiku for the translator's text mode" item gains: now a `model = haiku` config edit rather than a code change.
5. `mynah-vault/Design/configurable-language-pair.md` — change the status line from "designed, not implemented" to shipped, dated.

- [ ] **Step 7: Check nothing still claims Russian**

Run: `grep -rn "English → Russian\|English into Russian\|Russian only" --include='*.md' --include='*.swift' . | grep -v 'mynah-vault/Sessions\|docs/superpowers/plans'`
Expected: only `mynah-vault/Design/ad-hoc-translator.md`'s superseded note and `Decisions/0012`'s context paragraph, which describe history on purpose.

- [ ] **Step 8: Run the whole suite one more time**

Run: `make test`
Expected: PASS, 93 tests, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add CLAUDE.md README.md cli/README.md mynah-vault/
git commit -m "Document the configurable language pair"
```

---

## Notes for the executor

- **Do not add a default value for `ClaudeCLITranslator.languages`.** Every call site must name its pair. Task 3 updates the two existing call sites to a compiling stopgap (`try MynahConfig.load()` in the CLI, `MynahConfig.default` in the app) precisely so the suite still runs; Tasks 4 and 5 take them to their final forms, and Task 5's manual verification is what catches an `AppDelegate` left on `.default`.
- **Do not touch `ClaudeCLIEvaluator`, `CheckCoordinator`, or the `check` subcommand.** `mynah check` staying English-only is a locked decision, not an oversight.
- **No new package dependency.** If parsing feels like it wants TOML, it does not — the file has three keys.
- The manual steps in Tasks 4 and 5 call the real `claude` binary and cost real tokens; they are the only way to prove the prompts still work after the rewrite, so do not skip them.
