# Phase 2: Menu-bar Evaluator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu-bar (accessory) macOS app where the global hotkey ⌃⌥C runs the existing traffic-light evaluator on the clipboard text and shows the verdict (🟢/🟡/🔴), an empty state (📋), or an error (⚠️) in the tray icon for ~4s, then reverts to neutral (⚪).

**Architecture:** One SwiftPM package, three targets. The evaluator moves into a shared `SpellCheckerCore` library consumed by both the existing `spell-checker` CLI and a new `SpellCheckerBar` AppKit app. No SwiftUI, no Xcode project — built and bundled into a `.app` via `make`.

**Tech Stack:** Swift 6, AppKit (`NSStatusItem`, `NSMenu`, `NSPasteboard`), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (Carbon-backed global hotkey), `claude -p` CLI backend, XCTest, GNU make.

Spec: [`spell-checker-vault/Design/phase2-menubar-evaluator.md`](../../../spell-checker-vault/Design/phase2-menubar-evaluator.md).

## Global Constraints

- **Swift 6 / macOS 13+** (`// swift-tools-version: 6.0`, `platforms: [.macOS(.v13)]`).
- **SwiftPM + `make` only — no Xcode project** (`.xcodeproj`). GUI frameworks ship with the CLT SDK.
- **Pure AppKit this slice — no SwiftUI.**
- **`KeyboardShortcuts` is a dependency of the app target only**, version `from: "1.9.0"`.
- **Reuse the evaluator — no duplication.** Evaluation logic lives once, in `SpellCheckerCore`.
- **Default shortcut: ⌃⌥C** (`KeyboardShortcuts.Key.c` + `[.control, .option]`).
- **Icon = emoji set as the status-item button title.** States: ⚪ neutral · ⏳ working · 🟢 · 🟡 · 🔴 · 📋 empty · ⚠️ error.
- **Result display ~4 seconds, then revert to neutral.**
- **No overlapping `claude` runs:** ignore ⌃⌥C while a check is in flight (`isChecking`). A press during the display window starts a fresh check.
- **Empty clipboard is NOT an error** → 📋 empty state. ⚠️ is reserved for `claude` failure / unparseable output.
- **Bundle id `io.klimov.spellchecker`, `LSUIElement=true`** (accessory app, no Dock icon).
- **Repo conventions:** plain descriptive commit titles (no ticket prefix — this is `~/pet`); never commit to `main` (work on branch `phase2-menubar-evaluator`, already checked out); never push without explicit instruction.

---

## File Structure

```
cli/
  Package.swift                                   MODIFY: 3 targets + test target + KeyboardShortcuts dep
  packaging/Info.plist                            CREATE: app bundle plist (LSUIElement)
  Sources/
    SpellCheckerCore/                             CREATE (library): shared evaluator + IconState
      Verdict.swift                               (moved from SpellChecker) public enum Verdict
      TextEvaluator.swift                         (moved) public protocol + prompt + EvaluationError
      ClaudeCLIEvaluator.swift                    (moved) public struct + PATH resolver + static parseVerdict
      IconState.swift                             CREATE: public enum IconState (glyph + isTransient)
    SpellChecker/                                 (existing CLI executable)
      main.swift                                  MODIFY: `import SpellCheckerCore`
    SpellCheckerBar/                              CREATE (app executable, AppKit)
      EntryPoint.swift                            @main NSApplication bootstrap (.accessory)
      AppDelegate.swift                           status item, menu, wiring
      StatusItemController.swift                  owns NSStatusItem, show(state:) + 4s revert
      CheckCoordinator.swift                      isChecking guard, clipboard read, evaluate, map→IconState
      Shortcuts.swift                             KeyboardShortcuts.Name.toggleCheck (default ⌃⌥C)
  Tests/
    SpellCheckerCoreTests/                        CREATE: unit tests for pure logic
      ParseVerdictTests.swift
      IconStateTests.swift
Makefile                                          MODIFY: app / run-app targets, clean dist
.gitignore                                        MODIFY: add dist/
README.md (cli/)                                  MODIFY: document the menu-bar app
spell-checker-vault/Sessions/2026-06-25-session-04-menubar-evaluator.md   CREATE
spell-checker-vault/Roadmap.md, Home.md           MODIFY: check Phase 2 box, link session
```

**Note on test scope.** Pure logic (`parseVerdict`, `IconState`) is unit-tested with XCTest. The `claude` shell-out and all AppKit UI are verified by **running the app** against the spec's checklist — they can't be meaningfully unit-tested without a live, authed `claude` and a real menu bar. Manual-verification steps are labelled as such and require `claude` installed and authenticated.

---

### Task 1: Extract `SpellCheckerCore` library; repoint the CLI

Move the evaluator out of the CLI executable into a library target both binaries can share. No behaviour change.

**Files:**
- Create: `cli/Sources/SpellCheckerCore/Verdict.swift` (from `cli/Sources/SpellChecker/TextEvaluator.swift`)
- Create: `cli/Sources/SpellCheckerCore/TextEvaluator.swift` (from same)
- Create: `cli/Sources/SpellCheckerCore/ClaudeCLIEvaluator.swift` (moved from `cli/Sources/SpellChecker/ClaudeCLIEvaluator.swift`)
- Delete: `cli/Sources/SpellChecker/TextEvaluator.swift`, `cli/Sources/SpellChecker/ClaudeCLIEvaluator.swift`
- Modify: `cli/Sources/SpellChecker/main.swift:1` (add import)
- Modify: `cli/Package.swift` (whole file)

**Interfaces:**
- Produces (public API of `SpellCheckerCore`):
  - `public enum Verdict: String, Sendable { case red, yellow, green; public var display: String }`
  - `public protocol TextEvaluator: Sendable { func evaluate(_ text: String) throws -> Verdict }`
  - `public struct ClaudeCLIEvaluator: TextEvaluator { public init(model: String = "sonnet"); public func evaluate(_ text: String) throws -> Verdict }`
  - Internal: `evaluationPrompt`, `struct EvaluationError`, `static func parseVerdict(from:)`.

- [ ] **Step 1: Create `cli/Sources/SpellCheckerCore/Verdict.swift`**

```swift
import Foundation

/// A traffic-light verdict on a piece of text.
///
/// red vs. yellow is a *comprehension* line: red means a reader might
/// misunderstand; yellow means they'll understand but it reads non-native.
public enum Verdict: String, Sendable {
    case red, yellow, green

    public var display: String {
        switch self {
        case .red:    return "🔴 red"
        case .yellow: return "🟡 yellow"
        case .green:  return "🟢 green"
        }
    }
}
```

- [ ] **Step 2: Create `cli/Sources/SpellCheckerCore/TextEvaluator.swift`**

```swift
import Foundation

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
```

- [ ] **Step 3: Create `cli/Sources/SpellCheckerCore/ClaudeCLIEvaluator.swift`**

Same logic as the existing file, but: `public struct`, `public init`, `public func evaluate`, and `parseVerdict` becomes an internal `static` method (so Task 2 can unit-test it). The PATH fix is a *separate* task (Task 3) — keep `runClaude` byte-for-byte as it was here.

```swift
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
```

- [ ] **Step 4: Delete the old CLI copies**

Run:
```bash
git rm cli/Sources/SpellChecker/TextEvaluator.swift cli/Sources/SpellChecker/ClaudeCLIEvaluator.swift
```
Expected: both files removed (their content now lives in `SpellCheckerCore`).

- [ ] **Step 5: Add the import to `cli/Sources/SpellChecker/main.swift`**

Change line 1 from:
```swift
import Foundation
```
to:
```swift
import Foundation
import SpellCheckerCore
```
Leave the rest of `main.swift` unchanged — `Verdict`, `TextEvaluator`, `ClaudeCLIEvaluator`, and `.display` now resolve from the imported module.

- [ ] **Step 6: Rewrite `cli/Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpellChecker",
    platforms: [.macOS(.v13)],
    products: [
        // Binary names are hyphenated; target/module names can't be, hence the split.
        .executable(name: "spell-checker", targets: ["SpellChecker"])
    ],
    targets: [
        .target(
            name: "SpellCheckerCore",
            path: "Sources/SpellCheckerCore"
        ),
        .executableTarget(
            name: "SpellChecker",
            dependencies: ["SpellCheckerCore"],
            path: "Sources/SpellChecker"
        )
    ]
)
```

- [ ] **Step 7: Build and verify the CLI still works**

Run:
```bash
cd cli && swift build 2>&1 | tail -20
```
Expected: `Build complete!` with no errors.

Run (no `claude` needed — exercises arg parsing + wiring):
```bash
swift run spell-checker --help
```
Expected: the usage text printed.

Optional (requires authed `claude`):
```bash
swift run spell-checker check "Thanks for the review, I've merged the branch."
```
Expected: `🟢 green`.

- [ ] **Step 8: Commit**

```bash
cd /Users/aleksey/pet/spell-checker
git add -A
git commit -F - <<'EOF'
Extract evaluator into a shared SpellCheckerCore library

- Move Verdict, TextEvaluator, ClaudeCLIEvaluator into SpellCheckerCore;
  make the consumed API public; parseVerdict becomes static (testable).
- CLI (SpellChecker target) now depends on and imports SpellCheckerCore.
- No behaviour change; groundwork for the menu-bar app target.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: Add the Core test target and `IconState`

Establish a test target and introduce the icon-state model (used by the app target later), driven by tests.

**Files:**
- Create: `cli/Sources/SpellCheckerCore/IconState.swift`
- Create: `cli/Tests/SpellCheckerCoreTests/IconStateTests.swift`
- Create: `cli/Tests/SpellCheckerCoreTests/ParseVerdictTests.swift`
- Modify: `cli/Package.swift` (add `.testTarget`)

**Interfaces:**
- Consumes: `Verdict`, `ClaudeCLIEvaluator.parseVerdict(from:)` (Task 1).
- Produces:
  - `public enum IconState: Sendable, Equatable { case neutral, working, empty, error, verdict(Verdict); public var glyph: String; public var isTransient: Bool }`

- [ ] **Step 1: Write the failing tests for `IconState`**

Create `cli/Tests/SpellCheckerCoreTests/IconStateTests.swift`:
```swift
import XCTest
@testable import SpellCheckerCore

final class IconStateTests: XCTestCase {
    func testGlyphs() {
        XCTAssertEqual(IconState.neutral.glyph, "⚪")
        XCTAssertEqual(IconState.working.glyph, "⏳")
        XCTAssertEqual(IconState.empty.glyph, "📋")
        XCTAssertEqual(IconState.error.glyph, "⚠️")
        XCTAssertEqual(IconState.verdict(.green).glyph, "🟢")
        XCTAssertEqual(IconState.verdict(.yellow).glyph, "🟡")
        XCTAssertEqual(IconState.verdict(.red).glyph, "🔴")
    }

    func testIsTransient() {
        // neutral and working persist until replaced; the rest auto-revert.
        XCTAssertFalse(IconState.neutral.isTransient)
        XCTAssertFalse(IconState.working.isTransient)
        XCTAssertTrue(IconState.empty.isTransient)
        XCTAssertTrue(IconState.error.isTransient)
        XCTAssertTrue(IconState.verdict(.green).isTransient)
    }
}
```

- [ ] **Step 2: Write the failing characterization tests for `parseVerdict`**

Create `cli/Tests/SpellCheckerCoreTests/ParseVerdictTests.swift`:
```swift
import XCTest
@testable import SpellCheckerCore

final class ParseVerdictTests: XCTestCase {
    func testPlainWord() throws {
        XCTAssertEqual(try ClaudeCLIEvaluator.parseVerdict(from: "green"), .green)
    }

    func testCaseInsensitiveWithSurroundingText() throws {
        XCTAssertEqual(try ClaudeCLIEvaluator.parseVerdict(from: "The verdict is RED."), .red)
    }

    func testEmojiPrefixed() throws {
        XCTAssertEqual(try ClaudeCLIEvaluator.parseVerdict(from: "🟡 yellow"), .yellow)
    }

    func testIgnoresSubstrings() throws {
        // "covered" contains "red" as a substring but is not a standalone token.
        XCTAssertEqual(
            try ClaudeCLIEvaluator.parseVerdict(from: "I covered everything; verdict: green"),
            .green
        )
    }

    func testNoVerdictThrows() {
        XCTAssertThrowsError(try ClaudeCLIEvaluator.parseVerdict(from: "no idea here"))
    }

    func testVerdictDisplay() {
        XCTAssertEqual(Verdict.red.display, "🔴 red")
        XCTAssertEqual(Verdict.yellow.display, "🟡 yellow")
        XCTAssertEqual(Verdict.green.display, "🟢 green")
    }
}
```

- [ ] **Step 3: Add the test target to `cli/Package.swift`**

Add this entry to the `targets:` array (after the `SpellChecker` executable target):
```swift
        .testTarget(
            name: "SpellCheckerCoreTests",
            dependencies: ["SpellCheckerCore"],
            path: "Tests/SpellCheckerCoreTests"
        )
```

- [ ] **Step 4: Run the tests to verify they FAIL to compile**

Run:
```bash
cd cli && swift test 2>&1 | tail -20
```
Expected: compilation failure — `cannot find 'IconState' in scope` (the type doesn't exist yet). `ParseVerdictTests` reference `ClaudeCLIEvaluator.parseVerdict`, which exists from Task 1, so the only failure is the missing `IconState`.

- [ ] **Step 5: Create `cli/Sources/SpellCheckerCore/IconState.swift`**

```swift
import Foundation

/// What the menu-bar icon shows. `verdict` wraps the traffic-light result so the
/// three colours share one case; the standalone cases cover the lifecycle.
public enum IconState: Sendable, Equatable {
    case neutral   // idle
    case working   // a check is running
    case empty     // clipboard had no text — nothing to check (NOT an error)
    case error     // claude failed or returned unparseable output
    case verdict(Verdict)

    /// Emoji rendered as the status-item button title.
    public var glyph: String {
        switch self {
        case .neutral: return "⚪"
        case .working: return "⏳"
        case .empty:   return "📋"
        case .error:   return "⚠️"
        case .verdict(let v):
            switch v {
            case .green:  return "🟢"
            case .yellow: return "🟡"
            case .red:    return "🔴"
            }
        }
    }

    /// True for states that should auto-revert to `.neutral` after the display
    /// window; false for `.neutral` (the resting state) and `.working` (replaced
    /// by the result, not by a timer).
    public var isTransient: Bool {
        switch self {
        case .neutral, .working: return false
        case .empty, .error, .verdict: return true
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they PASS**

Run:
```bash
cd cli && swift test 2>&1 | tail -20
```
Expected: all tests pass (`Test Suite 'All tests' passed`), 0 failures.

- [ ] **Step 7: Commit**

```bash
cd /Users/aleksey/pet/spell-checker
git add -A
git commit -F - <<'EOF'
Add Core test target and IconState model

- New XCTest target covering parseVerdict (lenient token scan), Verdict
  display strings, and the new IconState glyph/isTransient mapping.
- IconState models the seven menu-bar icon states for the app target.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: Fix `claude` resolution for GUI launch (absolute-path resolver)

A `.app` launched from Finder does not inherit the shell `PATH`, so `/usr/bin/env claude` fails. Resolve `claude`'s absolute path from known install locations; fall back to the current `env` behaviour (which works from a terminal).

**Files:**
- Modify: `cli/Sources/SpellCheckerCore/ClaudeCLIEvaluator.swift` (`runClaude` + a new static resolver)

**Interfaces:**
- Consumes: nothing new.
- Produces: internal `static func resolveClaudeURL() -> URL` (no public API change).

- [ ] **Step 1: Add the resolver and use it in `runClaude`**

In `cli/Sources/SpellCheckerCore/ClaudeCLIEvaluator.swift`, add this static method (e.g. right after `parseVerdict`):
```swift
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
```

Then change the top of `runClaude` from:
```swift
        let process = Process()
        // Resolve `claude` from PATH (it lives in ~/.local/bin).
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "-p", "--model", model]
```
to:
```swift
        let process = Process()
        // GUI apps don't inherit the shell PATH — resolve claude's absolute path,
        // falling back to `/usr/bin/env claude` for terminal runs.
        let claudeURL = Self.resolveClaudeURL()
        process.executableURL = claudeURL
        process.arguments = claudeURL.lastPathComponent == "env"
            ? ["claude", "-p", "--model", model]
            : ["-p", "--model", model]
```

- [ ] **Step 2: Build**

Run:
```bash
cd cli && swift build 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: Verify the CLI still evaluates (manual; requires authed `claude`)**

Run:
```bash
cd cli && swift run spell-checker check "Please send the file to Anna and her assistant when she is ready."
```
Expected: `🔴 red` (the verified ambiguous example). This confirms the resolver found `claude` and the shell-out still works.

- [ ] **Step 4: Run the unit tests (regression)**

Run:
```bash
cd cli && swift test 2>&1 | tail -5
```
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/aleksey/pet/spell-checker
git add -A
git commit -F - <<'EOF'
Resolve claude's absolute path (GUI apps don't inherit shell PATH)

- Add resolveClaudeURL(): prefer ~/.local/bin, Homebrew, /usr/local/bin;
  fall back to `/usr/bin/env claude` for terminal runs.
- Lets the upcoming .app find claude when launched from Finder.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: `SpellCheckerBar` skeleton — neutral status item + Quit

A runnable accessory app that shows the neutral icon and a Quit menu. No hotkey, no evaluation yet.

**Files:**
- Create: `cli/Sources/SpellCheckerBar/EntryPoint.swift`
- Create: `cli/Sources/SpellCheckerBar/AppDelegate.swift`
- Modify: `cli/Package.swift` (add `spell-checker-bar` product + `SpellCheckerBar` target)

**Interfaces:**
- Consumes: `IconState` (Task 2).
- Produces: `@MainActor final class AppDelegate: NSObject, NSApplicationDelegate` (extended in Tasks 5–6).

- [ ] **Step 1: Add the app product and target to `cli/Package.swift`**

Add to `products:`:
```swift
        .executable(name: "spell-checker-bar", targets: ["SpellCheckerBar"])
```
Add to `targets:` (after the `SpellChecker` executable target):
```swift
        .executableTarget(
            name: "SpellCheckerBar",
            dependencies: ["SpellCheckerCore"],
            path: "Sources/SpellCheckerBar"
        ),
```
(Leave the `.testTarget` last.)

- [ ] **Step 2: Create `cli/Sources/SpellCheckerBar/EntryPoint.swift`**

```swift
import AppKit

/// Menu-bar (accessory) app entry point. No storyboard, no Dock icon.
/// Lives in a non-`main.swift` file so we can use `@main`.
@main
@MainActor
struct SpellCheckerBarApp {
    static func main() {
        let app = NSApplication.shared
        // Retain the delegate for the whole run: NSApplication.delegate is weak,
        // and app.run() blocks until quit, so this local stays alive.
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu-bar only; no Dock icon
        app.run()
    }
}
```

- [ ] **Step 3: Create `cli/Sources/SpellCheckerBar/AppDelegate.swift`**

```swift
import AppKit
import SpellCheckerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = IconState.neutral.glyph

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit Spell Checker",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu

        self.statusItem = item
    }
}
```

- [ ] **Step 4: Build**

Run:
```bash
cd cli && swift build --product spell-checker-bar 2>&1 | tail -10
```
Expected: `Build complete!`

- [ ] **Step 5: Verify by running (manual)**

Run:
```bash
cd cli && swift run spell-checker-bar
```
Expected: a **⚪** icon appears in the menu bar; **no Dock icon** appears. Click the icon → a menu with **Quit Spell Checker** appears. Choose Quit (or press ⌃C in the terminal) to stop. Confirm the icon disappears on quit.

- [ ] **Step 6: Commit**

```bash
cd /Users/aleksey/pet/spell-checker
git add -A
git commit -F - <<'EOF'
Add SpellCheckerBar app skeleton (menu-bar status item + Quit)

- New accessory executable target (AppKit, no Dock icon): shows the
  neutral ⚪ icon and a Quit menu item. No hotkey/evaluation yet.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: Live evaluation flow — `StatusItemController` + `CheckCoordinator` + menu trigger

Wire the real flow: a "Check clipboard now" menu item reads the clipboard, runs the evaluator, and drives the icon (⏳ → result → ⚪). The menu item is both a shipped feature and the verification seam (the hotkey in Task 6 reuses the same path).

**Files:**
- Create: `cli/Sources/SpellCheckerBar/StatusItemController.swift`
- Create: `cli/Sources/SpellCheckerBar/CheckCoordinator.swift`
- Modify: `cli/Sources/SpellCheckerBar/AppDelegate.swift`

**Interfaces:**
- Consumes: `IconState`, `TextEvaluator`, `ClaudeCLIEvaluator` (Core).
- Produces:
  - `@MainActor final class StatusItemController { init(); var button: NSStatusBarButton?; func setMenu(_ menu: NSMenu); func show(_ state: IconState) }`
  - `@MainActor final class CheckCoordinator { init(status: StatusItemController, evaluator: any TextEvaluator); func runCheck() }`

- [ ] **Step 1: Create `cli/Sources/SpellCheckerBar/StatusItemController.swift`**

```swift
import AppKit
import SpellCheckerCore

/// Owns the menu-bar status item and renders an `IconState`. Transient states
/// auto-revert to `.neutral` after `displayDuration`.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private var revertTimer: Timer?
    private let displayDuration: TimeInterval = 4

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = IconState.neutral.glyph
    }

    var button: NSStatusBarButton? { statusItem.button }

    func setMenu(_ menu: NSMenu) { statusItem.menu = menu }

    /// Render `state`. Any pending revert is cancelled first, so a fresh result
    /// (or a new `.working`) restarts the cycle cleanly.
    func show(_ state: IconState) {
        revertTimer?.invalidate()
        revertTimer = nil
        statusItem.button?.title = state.glyph
        guard state.isTransient else { return }
        revertTimer = Timer.scheduledTimer(
            withTimeInterval: displayDuration, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.show(.neutral) }
        }
    }
}
```

- [ ] **Step 2: Create `cli/Sources/SpellCheckerBar/CheckCoordinator.swift`**

```swift
import AppKit
import Foundation
import SpellCheckerCore

/// Orchestrates one check: guards against overlap, reads the clipboard, runs the
/// evaluator off the main thread, and maps the outcome to an `IconState`.
@MainActor
final class CheckCoordinator {
    private let status: StatusItemController
    private let evaluator: any TextEvaluator
    private var isChecking = false

    init(status: StatusItemController, evaluator: any TextEvaluator) {
        self.status = status
        self.evaluator = evaluator
    }

    func runCheck() {
        // Ignore re-triggers while a check is in flight — no overlapping runs.
        guard !isChecking else { return }

        let text = (NSPasteboard.general.string(forType: .string) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status.show(.empty)  // nothing to check — not an error
            return
        }

        isChecking = true
        status.show(.working)
        let evaluator = self.evaluator
        Task {
            let state = await Self.evaluate(evaluator, text)
            self.isChecking = false
            self.status.show(state)
        }
    }

    /// Run the (blocking) evaluator off the main actor and map to an IconState.
    private static func evaluate(_ evaluator: any TextEvaluator, _ text: String) async -> IconState {
        await Task.detached(priority: .userInitiated) {
            do {
                return IconState.verdict(try evaluator.evaluate(text))
            } catch {
                FileHandle.standardError.write(Data("spell-checker-bar: \(error)\n".utf8))
                return IconState.error
            }
        }.value
    }
}
```

- [ ] **Step 3: Rewrite `cli/Sources/SpellCheckerBar/AppDelegate.swift` to use them**

```swift
import AppKit
import SpellCheckerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusItemController!
    private var coordinator: CheckCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusItemController()
        coordinator = CheckCoordinator(status: status, evaluator: ClaudeCLIEvaluator())

        let menu = NSMenu()
        let checkItem = NSMenuItem(
            title: "Check clipboard now",
            action: #selector(checkNow),
            keyEquivalent: ""
        )
        checkItem.target = self
        menu.addItem(checkItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Spell Checker",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        status.setMenu(menu)
    }

    @objc private func checkNow() {
        coordinator.runCheck()
    }
}
```

- [ ] **Step 4: Build**

Run:
```bash
cd cli && swift build --product spell-checker-bar 2>&1 | tail -15
```
Expected: `Build complete!` (no Swift 6 concurrency errors — all UI types are `@MainActor`, `IconState`/`Verdict`/`TextEvaluator` are `Sendable`).

- [ ] **Step 5: Verify the full evaluation flow (manual; requires authed `claude`)**

Run `cd cli && swift run spell-checker-bar`, then for each case copy the text to the clipboard and pick **Check clipboard now** from the menu:

| copy this to clipboard | expected icon sequence |
|---|---|
| `Thanks for the review, I've merged the branch.` | ⏳ → 🟢 → (after ~4s) ⚪ |
| `Please send the file to Anna and her assistant when she is ready.` | ⏳ → 🔴 → ⚪ |
| `i has finished the task and it works good now please to review when you has time thanks` | ⏳ → 🟡 → ⚪ |
| *(clear the clipboard: `pbcopy </dev/null`)* | 📋 → ⚪ (no ⏳; not an error) |

Also verify **no overlap**: copy a long text, choose **Check clipboard now**, then immediately choose it again while ⏳ is showing — the second pick is ignored (still one result, no flicker to a second ⏳). Quit when done.

- [ ] **Step 6: Commit**

```bash
cd /Users/aleksey/pet/spell-checker
git add -A
git commit -F - <<'EOF'
Wire the live evaluation flow into the menu-bar app

- StatusItemController renders IconState and auto-reverts transient states
  to neutral after ~4s.
- CheckCoordinator guards overlap (isChecking), reads the clipboard, runs
  the evaluator off the main actor, and maps the result/empty/error to an icon.
- "Check clipboard now" menu item triggers a check end-to-end.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: Global hotkey ⌃⌥C via KeyboardShortcuts

Add the dependency and bind ⌃⌥C to the same `runCheck()` path.

**Files:**
- Create: `cli/Sources/SpellCheckerBar/Shortcuts.swift`
- Modify: `cli/Package.swift` (add dependency + target dependency)
- Modify: `cli/Sources/SpellCheckerBar/AppDelegate.swift` (register the handler)

**Interfaces:**
- Consumes: `CheckCoordinator.runCheck()` (Task 5).
- Produces: `KeyboardShortcuts.Name.toggleCheck` (default ⌃⌥C).

- [ ] **Step 1: Add the KeyboardShortcuts dependency to `cli/Package.swift`**

Add a top-level `dependencies:` array to the `Package(...)` (between `products:` and `targets:`):
```swift
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.9.0")
    ],
```
Add the product to the `SpellCheckerBar` target's `dependencies`:
```swift
        .executableTarget(
            name: "SpellCheckerBar",
            dependencies: [
                "SpellCheckerCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/SpellCheckerBar"
        ),
```

- [ ] **Step 2: Resolve the dependency (requires network, first time only)**

Run:
```bash
cd cli && swift package resolve 2>&1 | tail -10
```
Expected: KeyboardShortcuts resolved at a 1.9.x version (e.g. `1.9.4`). If offline, this fails — rerun when online.

- [ ] **Step 3: Create `cli/Sources/SpellCheckerBar/Shortcuts.swift`**

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global hotkey that triggers a clipboard check. Default: ⌃⌥C.
    /// User-rebindable recorder UI is deferred (see vault inbox).
    static let toggleCheck = Self(
        "toggleCheck",
        default: .init(.c, modifiers: [.control, .option])
    )
}
```

- [ ] **Step 4: Register the handler in `applicationDidFinishLaunching`**

In `cli/Sources/SpellCheckerBar/AppDelegate.swift`, add the import at the top:
```swift
import KeyboardShortcuts
```
Then add this at the end of `applicationDidFinishLaunching(_:)` (after `status.setMenu(menu)`):
```swift
        // KeyboardShortcuts invokes the handler on the main thread; assumeIsolated
        // bridges it to our @MainActor coordinator across Swift 6 isolation checks.
        KeyboardShortcuts.onKeyDown(for: .toggleCheck) { [weak self] in
            MainActor.assumeIsolated {
                self?.coordinator.runCheck()
            }
        }
```

- [ ] **Step 5: Build**

Run:
```bash
cd cli && swift build --product spell-checker-bar 2>&1 | tail -15
```
Expected: `Build complete!`

- [ ] **Step 6: Verify the hotkey (manual; requires authed `claude`)**

Run `cd cli && swift run spell-checker-bar`. Copy `Thanks for the review, I've merged the branch.` to the clipboard, then press **⌃⌥C** (Control+Option+C). Expected: ⏳ → 🟢 → ⚪ — identical to the menu trigger, but from the keyboard, and it works even when another app is frontmost. Press ⌃⌥C twice quickly → the second press is ignored while ⏳ shows. Quit when done.

- [ ] **Step 7: Commit**

```bash
cd /Users/aleksey/pet/spell-checker
git add -A
git commit -F - <<'EOF'
Add global hotkey ⌃⌥C (KeyboardShortcuts) to trigger a check

- Add KeyboardShortcuts dependency (app target only), default shortcut
  Control+Option+C bound to the same runCheck() path as the menu item.
- Carbon-backed, so no Accessibility permission prompt.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 7: Bundle the `.app` via `make`, document, and close out Phase 2

Assemble a launchable `.app`, verify it from Finder (where the PATH fix matters), and update docs + vault.

**Files:**
- Create: `cli/packaging/Info.plist`
- Modify: `Makefile`
- Modify: `.gitignore` (add `dist/`)
- Modify: `cli/README.md`
- Create: `spell-checker-vault/Sessions/2026-06-25-session-04-menubar-evaluator.md`
- Modify: `spell-checker-vault/Roadmap.md` (check Phase 2 box, link session)
- Modify: `spell-checker-vault/Home.md` (add session to the Sessions line)

- [ ] **Step 1: Create `cli/packaging/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>Spell Checker</string>
    <key>CFBundleDisplayName</key>        <string>Spell Checker</string>
    <key>CFBundleIdentifier</key>         <string>io.klimov.spellchecker</string>
    <key>CFBundleExecutable</key>         <string>SpellChecker</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>LSMinimumSystemVersion</key>     <string>13.0</string>
    <key>LSUIElement</key>                <true/>
</dict>
</plist>
```

- [ ] **Step 2: Add `app` / `run-app` targets to the `Makefile`**

Add these variables near the top (after `BIN := spell-checker`):
```make
APP    := SpellChecker
APPBIN := spell-checker-bar
APPDIR := $(PKGDIR)/dist/$(APP).app
PLIST  := $(PKGDIR)/packaging/Info.plist
```
Update the `.PHONY` line to include the new targets:
```make
.PHONY: help build install uninstall clean app run-app
```
Add the targets (e.g. after `install:`):
```make
app: ## build the menu-bar app bundle (dist/SpellChecker.app)
	cd $(PKGDIR) && swift build -c release --product $(APPBIN)
	rm -rf $(APPDIR)
	mkdir -p $(APPDIR)/Contents/MacOS
	cp $(PKGDIR)/.build/release/$(APPBIN) $(APPDIR)/Contents/MacOS/$(APP)
	cp $(PLIST) $(APPDIR)/Contents/Info.plist
	codesign --force --sign - $(APPDIR)
	@echo ""
	@echo "✅ built $(APPDIR)"
	@echo "   open it:  make run-app   (or double-click in Finder)"
	@echo "   hotkey:   ⌃⌥C checks the clipboard"

run-app: app
	open $(APPDIR)
```
Update the `clean` target to also remove the bundle:
```make
clean:
	cd $(PKGDIR) && swift package clean
	rm -rf $(APPDIR)
```
Add lines to the `help:` block:
```make
	@echo "  make app         build the menu-bar app bundle (dist/SpellChecker.app)"
	@echo "  make run-app     build the app bundle and open it"
```

- [ ] **Step 3: Ignore the build output**

In `.gitignore`, under the `# Swift Package Manager` section, add:
```
dist/
```

- [ ] **Step 4: Build and launch the bundle from Finder (manual; requires authed `claude`)**

Run:
```bash
make run-app
```
Expected: `✅ built cli/dist/SpellChecker.app`, then the app launches (⚪ in the menu bar, no Dock icon). **This is the key PATH test** — the app is launched by `open` (Finder-style, no shell PATH). Copy `Please send the file to Anna and her assistant when she is ready.` and press **⌃⌥C** → ⏳ → 🔴 → ⚪. If it shows ⚠️, the resolver in Task 3 didn't find `claude` — investigate before proceeding. Run the full checklist from Task 5 Step 5 against the bundled app. Quit via the menu.

- [ ] **Step 5: Verify the CLI is unbroken (regression) and tests pass**

Run:
```bash
make build && cd cli && swift test 2>&1 | tail -5
```
Expected: build succeeds and all unit tests pass.

- [ ] **Step 6: Update `cli/README.md`**

Change the title line 1 from:
```markdown
# spell-checker — CLI evaluator (Phase 1)
```
to:
```markdown
# spell-checker — CLI evaluator + menu-bar app
```
Add this section after the `## Dev (without installing)` section:
```markdown
## Menu-bar app (Phase 2)

A menu-bar app wraps the same evaluator. Press **⌃⌥C** (Control+Option+C) to evaluate whatever
is on the clipboard; the tray icon shows the verdict for ~4s, then reverts:

⚪ idle · ⏳ checking · 🟢 / 🟡 / 🔴 verdict · 📋 clipboard empty · ⚠️ error

```sh
make app        # build dist/SpellChecker.app
make run-app    # build and open it
```

It's an accessory app (no Dock icon) and quits from its menu. The shortcut is hardcoded for now;
a rebind UI is planned (see the vault inbox). Dev run without bundling: `cd cli && swift run spell-checker-bar`.
```

- [ ] **Step 7: Write the session note**

Create `spell-checker-vault/Sessions/2026-06-25-session-04-menubar-evaluator.md`:
```markdown
# Session 04 — Menu-bar evaluator (2026-06-25)

## Goal

Ship [[Roadmap|Phase 2]]: a menu-bar app where ⌃⌥C evaluates the clipboard and shows the
traffic-light verdict in the tray icon. Design: [[phase2-menubar-evaluator]].

## What we did

- Extracted the evaluator into a shared **`SpellCheckerCore`** library; the CLI and the new
  **`SpellCheckerBar`** app both depend on it (no duplication).
- Added a Core **test target** (parseVerdict, Verdict.display, IconState).
- Built the AppKit app: `StatusItemController` (icon + ~4s revert), `CheckCoordinator`
  (overlap guard, clipboard read, off-main evaluate, map to `IconState`), global hotkey **⌃⌥C**
  via `KeyboardShortcuts`, and a "Check clipboard now" menu item.
- Fixed `claude` resolution so a Finder-launched `.app` finds it (absolute-path resolver,
  not the shell PATH) — touches [[0006-polish-backend-claude-cli]].
- `make app` / `make run-app` assemble `dist/SpellChecker.app` (`LSUIElement`, ad-hoc signed).

## Verified

- Unit tests pass; CLI unchanged.
- Bundled app launched from Finder: clear → 🟢, ambiguous → 🔴, error-heavy-but-clear → 🟡,
  empty clipboard → 📋, two fast ⌃⌥C → one run. Quit works. No Dock icon.

## Notes

- Built entirely with SwiftPM + `make` — no Xcode project ([[0003-build-toolchain-xcode-later]]).
- Deferred (in [[inbox]]): shortcut recorder UI, history/cache for instant repeats, richer text
  input. Overlap edge case tracked in [[concurrent-recheck-while-busy]].

## Next step

Phase 3 — the rewrite/polish loop (pillar 1): a typed-in popup that returns one revised version,
which also unlocks richer text input.
```

- [ ] **Step 8: Check the Phase 2 box and link the session in the Roadmap**

In `spell-checker-vault/Roadmap.md`, change the Phase 2 checkbox from `- [ ]` to `- [x]` and append the session link to its heading line:
```markdown
- [x] **Phase 2 — Menu-bar evaluator (hotkey → verdict in the tray icon)**
  *(design: [[phase2-menubar-evaluator]] · [[2026-06-25-session-04-menubar-evaluator]])*
```
(Leave the rest of the Phase 2 description as-is.)

- [ ] **Step 9: Add the session to `Home.md`**

In `spell-checker-vault/Home.md`, on the `📓 **Sessions**` line, append:
```markdown
 · [[2026-06-25-session-04-menubar-evaluator]]
```

- [ ] **Step 10: Commit**

```bash
cd /Users/aleksey/pet/spell-checker
git add -A
git commit -F - <<'EOF'
Bundle the menu-bar app via make; document and close out Phase 2

- make app / run-app assemble dist/SpellChecker.app (LSUIElement, ad-hoc
  signed); gitignore dist/.
- README documents the menu-bar app and icon states.
- Vault: session 04 note, Phase 2 checked off, Home sessions updated.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

## Self-Review

**1. Spec coverage** — every spec section maps to a task:
- Accessory app + neutral icon → T4. Quit menu → T4.
- ⌃⌥C hotkey (KeyboardShortcuts, default, Carbon) → T6.
- Working icon, clipboard read, empty→📋, evaluate via Core, verdict/error icons, ~4s revert → T5 (+ IconState T2).
- Overlap guard (isChecking) + fresh check during display → T5.
- Shared `SpellCheckerCore` (no duplication) → T1.
- Seven icon states → T2 (model) + T5 (render).
- `make app`/`run-app`, Info.plist `LSUIElement`, ad-hoc sign → T7.
- PATH-from-Finder fix → T3 (verified under Finder launch in T7).
- CLI regression → T1, T7.

**2. Placeholder scan** — no TBD/TODO-as-work, no "add error handling" hand-waving; every code step shows complete code, every command shows expected output. The only "TODO" is the intentional product TODO (richer input) tracked in the vault, not a plan gap.

**3. Type consistency** — names used across tasks match: `IconState` cases (`.neutral/.working/.empty/.error/.verdict(_)`) and `.glyph`/`.isTransient` (T2) are consumed exactly in `StatusItemController.show(_:)` and `CheckCoordinator` (T5); `ClaudeCLIEvaluator(model:)` public init (T1) used in T5; `parseVerdict(from:)` static internal (T1) called in tests (T2); `KeyboardShortcuts.Name.toggleCheck` (T6) matches the `onKeyDown(for:)` registration (T6); `runCheck()` (T5) reused by the hotkey (T6); `resolveClaudeURL()` (T3) used in `runClaude` (T3). `TextEvaluator: Sendable` + `IconState: Sendable` satisfy the `Task.detached` capture in T5.
