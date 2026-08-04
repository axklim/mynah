# Translator Slice 1 — Shared Input Guards, Nerd Font Icons, Hyper+C

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the checker's input guards into one shared, tested rule in `SpellCheckerCore` (adding the character limit it never had), replace the menu-bar emoji with tinted Nerd Font glyphs, and rebind the hotkey to Hyper+C — the groundwork slice for the ad-hoc translator.

**Architecture:** `SpellCheckerCore` gains two pure, dependency-free types: `InputText` (trim → reject empty → reject over 2000 characters) and a reworked `IconState` that exposes a Nerd Font glyph plus an `IconTint` enum. Core stays AppKit-free; the Bar target's `StatusItemController` maps `IconTint` to `NSColor` and renders an `NSAttributedString`, falling back to the old emoji when the font is absent. The CLI and `CheckCoordinator` both consume `InputText` instead of their own inline checks.

**Tech Stack:** Swift 6, SwiftPM (no Xcode project), XCTest, AppKit, CoreText, `KeyboardShortcuts` (already a dependency), `make`.

**Spec:** `spell-checker-vault/Design/ad-hoc-translator.md` (approved, committed `9277370`). This plan covers **slice 1 only** — `spell-checker translate` (slice 2) and the floating window (slice 3) get their own plans.

## Global Constraints

- **Branch:** `ad-hoc-translator`. Never commit to `main`. Never `git commit --amend`, never rewrite history — fix mistakes with a new commit.
- **Commit titles:** plain descriptive, **no ticket prefix** (this repo is under `~/pet`). No `Test plan` sections anywhere. **Every commit message must end with the trailer** `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>` — required by the user's global instructions. *(Added mid-execution: Tasks 1–6 and the controller's own commits omitted it, and it cannot be backfilled without rewriting history, which is forbidden.)*
- **Swift 6**, platform floor **macOS 13** (`cli/Package.swift`). **No new package dependencies.**
- **`SpellCheckerCore` stays UI-framework-free.** No AppKit, no SwiftUI anywhere in the target — those appear only in `SpellCheckerBar` and in test files. Foundation is fine and already present (`ClaudeCLIEvaluator.swift`). **Every file imports what it uses:** Swift imports are file-scoped, so a file calling Foundation APIs declares `import Foundation` itself rather than relying on a sibling's import leaking across the module. *(Corrected during execution — the original wording told Task 1 to add no import at all, which was wrong; see the ledger ruling.)*
- **Character limit is exactly `2000`**, counted with `String.count` (characters) **after** trimming — never `utf8.count`.
- **Nerd Font glyphs are written as `\u{f111}` escapes, never as pasted literal characters.** These are private-use codepoints that corrupt when retyped out of a rendered terminal.
- **Font:** `JetBrainsMonoNF-Regular` — the PostScript name. Not `JetBrainsMonoNerdFont-Regular` (a filename) and not the `NFM` mono variant.
- **Hotkey:** Hyper+C = `.c` with `[.control, .option, .command]`.
- **`Verdict.display` keeps its emoji forever** — that's terminal output, where 🟢 is correct.
- **Tests:** XCTest (not swift-testing), in the existing `cli/Tests/SpellCheckerCoreTests/`. Run with `cd cli && swift test`.
- **Any test needing the Nerd Font must skip, not fail, when it is absent** (`throw XCTSkip(...)`).

---

## File Structure

**Create:**
- `cli/Sources/SpellCheckerCore/InputText.swift` — the shared guard rule. Pure, no imports.
- `cli/Tests/SpellCheckerCoreTests/InputTextTests.swift` — guard edge cases.
- `cli/Tests/SpellCheckerCoreTests/IconFontCoverageTests.swift` — asserts the font covers every declared codepoint; skips when absent.

**Modify:**
- `cli/Sources/SpellCheckerCore/IconState.swift` — add `.tooLong`, swap emoji for Nerd Font glyphs, add `IconTint`, `tint`, `emojiGlyph`, `allStates`.
- `cli/Sources/SpellChecker/main.swift:28-44` — the `check` command consumes `InputText`.
- `cli/Sources/SpellCheckerBar/CheckCoordinator.swift:18-37` — `runCheck()` consumes `InputText`.
- `cli/Sources/SpellCheckerBar/StatusItemController.swift` — render an attributed title with font + tint, emoji fallback.
- `cli/Sources/SpellCheckerBar/Shortcuts.swift:4-9` — rebind to Hyper+C.
- `cli/Tests/SpellCheckerCoreTests/IconStateTests.swift` — updated expectations.
- `Makefile:52` — the printed hotkey hint; plus a new `test` target.
- `CLAUDE.md:57-58`, `README.md:23,37`, `cli/README.md:57,60` — hotkey and icon legend.
- `spell-checker-vault/Spec.md:24`, `spell-checker-vault/Roadmap.md:25`, `spell-checker-vault/Design/phase2-menubar-evaluator.md`, `spell-checker-vault/Problems/concurrent-recheck-while-busy.md`, `spell-checker-vault/Ideas/inbox.md:8-10`, `spell-checker-vault/Design/ad-hoc-translator.md` — same, plus two spec corrections.

**Do NOT touch — historical records, correct as written:**
- `docs/superpowers/plans/2026-06-25-phase2-menubar-evaluator.md` (a completed plan)
- `spell-checker-vault/Sessions/*` (session logs)
- This plan file, once committed.

---

### Task 1: `InputText` — the shared guard rule

The checker's guards are inline in two places today and **neither has a length limit**, so a stray ⌘A⌘C of a whole page goes to Claude in full. This task creates the rule; Tasks 2 and 6 adopt it.

**Files:**
- Create: `cli/Sources/SpellCheckerCore/InputText.swift`
- Test: `cli/Tests/SpellCheckerCoreTests/InputTextTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `InputCheck` (`.ok(String)` / `.noText` / `.tooLong(count: Int)`, `Sendable & Equatable`) and `InputText.check(_ raw: String?) -> InputCheck`, plus `InputText.characterLimit: Int` (= 2000). `.ok` carries the **trimmed** text; callers must use that value rather than re-trimming their own copy.

- [ ] **Step 1: Write the failing tests**

Create `cli/Tests/SpellCheckerCoreTests/InputTextTests.swift`:

```swift
import XCTest
@testable import SpellCheckerCore

final class InputTextTests: XCTestCase {
    func testNilIsNoText() {
        XCTAssertEqual(InputText.check(nil), .noText)
    }

    func testEmptyIsNoText() {
        XCTAssertEqual(InputText.check(""), .noText)
    }

    func testWhitespaceOnlyIsNoText() {
        XCTAssertEqual(InputText.check("   \n\t  "), .noText)
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(InputText.check("  hello  \n"), .ok("hello"))
    }

    func testExactlyAtLimitIsOk() {
        let text = String(repeating: "a", count: InputText.characterLimit)
        XCTAssertEqual(InputText.check(text), .ok(text))
    }

    func testOneOverLimitIsTooLong() {
        let over = InputText.characterLimit + 1
        XCTAssertEqual(
            InputText.check(String(repeating: "a", count: over)),
            .tooLong(count: over)
        )
    }

    func testLimitAppliesAfterTrimming() {
        // Padding must not push an otherwise-legal payload over the limit.
        let payload = String(repeating: "a", count: InputText.characterLimit)
        XCTAssertEqual(InputText.check("  \n" + payload + "\n  "), .ok(payload))
    }

    func testCountsCharactersNotBytes() {
        // 1500 Cyrillic characters plus an em-dash: 1501 characters, but well
        // over 2000 UTF-8 bytes. A byte-based limit would wrongly reject this,
        // which is why the rule uses String.count.
        let text = String(repeating: "я", count: 1500) + "\u{2014}"
        XCTAssertEqual(text.count, 1501)
        XCTAssertGreaterThan(text.utf8.count, InputText.characterLimit)
        XCTAssertEqual(InputText.check(text), .ok(text))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd cli && swift test --filter InputTextTests`
Expected: **compile failure**, `cannot find 'InputText' in scope`. (With XCTest, a missing type is a build error, not a red test — that is the correct "failing" state here.)

- [ ] **Step 3: Write the implementation**

Create `cli/Sources/SpellCheckerCore/InputText.swift`:

```swift
/// The outcome of checking raw input before spending an LLM call on it.
public enum InputCheck: Sendable, Equatable {
    /// Usable input, already trimmed. Callers should use this value.
    case ok(String)
    /// Nil, empty, or whitespace only — nothing to work with. Not an error.
    case noText
    /// Past the character limit; almost always a misclick (a whole page pasted).
    case tooLong(count: Int)
}

/// One input rule shared by every surface: the CLI, the menu-bar check, and
/// (from slice 2) the translator. Each surface renders the rejections its own
/// way — stderr, an icon, or a line in a window — but the rule lives here.
public enum InputText {
    /// Maximum accepted length, in characters.
    ///
    /// Sized to sit above any real message (a long Slack post or PR description
    /// runs a few hundred to a couple of thousand characters) while rejecting an
    /// accidental full-page paste, which lands in the tens of thousands.
    public static let characterLimit = 2000

    /// Trim `raw`, then classify it.
    ///
    /// Counts **characters** (`String.count`), not bytes. Em-dashes and arrows
    /// already make the two diverge, and Cyrillic costs two UTF-8 bytes per
    /// character — a byte limit would silently halve any Russian text.
    public static func check(_ raw: String?) -> InputCheck {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noText }
        let count = trimmed.count
        guard count <= characterLimit else { return .tooLong(count: count) }
        return .ok(trimmed)
    }
}
```

The file starts with `import Foundation` — `trimmingCharacters(in:)` and `CharacterSet` are Foundation APIs, and Swift imports are **file-scoped**. Omitting it appears to work only because an import in a sibling file of the same module leaks across files, in both debug and whole-module release builds. That is undefined by contract and breaks the moment `ClaudeCLIEvaluator.swift` is refactored. *(This paragraph originally instructed the opposite; corrected during execution.)*

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd cli && swift test --filter InputTextTests`
Expected: **8 tests, all passing.**

- [ ] **Step 5: Commit**

```bash
git add cli/Sources/SpellCheckerCore/InputText.swift cli/Tests/SpellCheckerCoreTests/InputTextTests.swift
git commit -m "feat: add shared input guard with a 2000-character limit

One rule in SpellCheckerCore for every surface: trim, reject empty, reject
over 2000 characters. Counts characters, not bytes, so multibyte text is not
silently halved. Call sites adopt it next."
```

---

### Task 2: The CLI's `check` command consumes `InputText`

**Files:**
- Modify: `cli/Sources/SpellChecker/main.swift:28-44`

**Interfaces:**
- Consumes: `InputText.check(_:)`, `InputCheck`, `InputText.characterLimit` from Task 1.
- Produces: no new API. Exit code **2** for both rejections (matching the existing usage-error convention); exit **1** stays reserved for evaluator failures.

- [ ] **Step 1: Replace the inline guard**

In `cli/Sources/SpellChecker/main.swift`, the `case "check":` block currently reads:

```swift
case "check":
    let rest = Array(args.dropFirst())
    let text = (rest.isEmpty
        ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        : rest.joined(separator: " ")
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty else {
        fail("usage: spell-checker check <text>   (or pipe text via stdin)", code: 2)
    }
```

Replace it with:

```swift
case "check":
    let rest = Array(args.dropFirst())
    let raw = rest.isEmpty
        ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        : rest.joined(separator: " ")

    let text: String
    switch InputText.check(raw) {
    case .ok(let trimmed):
        text = trimmed
    case .noText:
        fail("usage: spell-checker check <text>   (or pipe text via stdin)", code: 2)
    case .tooLong(let count):
        fail(
            """
            error: input is \(count) characters, limit is \(InputText.characterLimit)
            That looks like an accidental paste — check what you copied.
            """,
            code: 2
        )
    }
```

Leave the rest of the block (the `ClaudeCLIEvaluator` call and its `do/catch`) untouched. `fail` returns `Never`, so the `switch` satisfies the `let text` initialisation.

- [ ] **Step 2: Build**

Run: `cd cli && swift build`
Expected: builds clean, no warnings about `text` being uninitialised.

- [ ] **Step 3: Verify both rejections and a real check**

Run each and confirm:

```bash
cd cli
swift run spell-checker check ""            # → usage message, exit 2
printf '' | swift run spell-checker check   # → usage message, exit 2
echo $?                                     # → 2

printf 'a%.0s' $(seq 2001) | swift run spell-checker check
# → "error: input is 2001 characters, limit is 2000", exit 2

printf 'a%.0s' $(seq 2000) | swift run spell-checker check
# → a real verdict (this one costs a claude call), exit 0
```

The 2000-character run proves the boundary is inclusive. Expect it to return 🟡 or 🔴 — 2000 letter `a`s are not a clear message — the point is only that it was *accepted*.

- [ ] **Step 4: Commit**

```bash
git add cli/Sources/SpellChecker/main.swift
git commit -m "refactor: CLI check uses the shared input guard

Drops the inline empty check and gains the length limit for free. Both
rejections exit 2; the too-long message names the count and the limit so it
is obvious whether the paste or the limit is wrong."
```

---

### Task 3: `IconState` — Nerd Font glyphs, tints, and `.tooLong`

**Files:**
- Modify: `cli/Sources/SpellCheckerCore/IconState.swift`
- Test: `cli/Tests/SpellCheckerCoreTests/IconStateTests.swift`

**Interfaces:**
- Consumes: `Verdict` (existing).
- Produces: `IconTint` (`.standard/.green/.yellow/.red/.orange/.secondary`); `IconState` case `.tooLong`; `IconState.glyph -> String` (now a Nerd Font escape), `IconState.tint -> IconTint`, `IconState.emojiGlyph -> String` (fallback), `IconState.allStates -> [IconState]`, and the existing `isTransient`. Task 5 consumes `glyph`, `tint`, `emojiGlyph`; Task 4 consumes `glyph` and `allStates`; Task 6 consumes `.tooLong`.

Naming note: the spec sketched the neutral tint as `.none`. This plan uses **`.standard`** instead — `.none` on an enum reads ambiguously against `Optional.none` at call sites. Task 9 corrects the spec.

- [ ] **Step 1: Write the failing tests**

Replace the whole body of `cli/Tests/SpellCheckerCoreTests/IconStateTests.swift`:

```swift
import XCTest
@testable import SpellCheckerCore

final class IconStateTests: XCTestCase {
    func testGlyphs() {
        // Nerd Font codepoints, written as escapes. Chosen by rendering them —
        // see Findings/nerd-font-codepoint-identity.
        XCTAssertEqual(IconState.neutral.glyph, "\u{f10c}")          // hollow circle
        XCTAssertEqual(IconState.working.glyph, "\u{f252}")          // hourglass
        XCTAssertEqual(IconState.empty.glyph, "\u{f016}")            // outlined page
        XCTAssertEqual(IconState.tooLong.glyph, "\u{f02d}")          // closed book
        XCTAssertEqual(IconState.error.glyph, "\u{f071}")            // warning triangle
        XCTAssertEqual(IconState.verdict(.green).glyph, "\u{f111}")  // filled circle
        XCTAssertEqual(IconState.verdict(.yellow).glyph, "\u{f111}")
        XCTAssertEqual(IconState.verdict(.red).glyph, "\u{f111}")
    }

    func testGlyphsAreSingleScalars() {
        // Guards against a pasted literal sneaking in: emoji like "⚠️" are two
        // scalars (base + variation selector), Nerd Font glyphs are always one.
        for state in IconState.allStates {
            XCTAssertEqual(
                state.glyph.unicodeScalars.count, 1,
                "\(state) glyph must be exactly one Unicode scalar"
            )
        }
    }

    func testTints() {
        // The three verdicts share one glyph and differ only by colour.
        XCTAssertEqual(IconState.neutral.tint, .standard)
        XCTAssertEqual(IconState.working.tint, .standard)
        XCTAssertEqual(IconState.empty.tint, .secondary)
        XCTAssertEqual(IconState.tooLong.tint, .secondary)
        XCTAssertEqual(IconState.error.tint, .orange)
        XCTAssertEqual(IconState.verdict(.green).tint, .green)
        XCTAssertEqual(IconState.verdict(.yellow).tint, .yellow)
        XCTAssertEqual(IconState.verdict(.red).tint, .red)
    }

    func testEmojiFallback() {
        // Used when the Nerd Font is missing, so the icon is never an empty box.
        XCTAssertEqual(IconState.neutral.emojiGlyph, "⚪")
        XCTAssertEqual(IconState.working.emojiGlyph, "⏳")
        XCTAssertEqual(IconState.empty.emojiGlyph, "📋")
        XCTAssertEqual(IconState.tooLong.emojiGlyph, "📏")
        XCTAssertEqual(IconState.error.emojiGlyph, "⚠️")
        XCTAssertEqual(IconState.verdict(.green).emojiGlyph, "🟢")
        XCTAssertEqual(IconState.verdict(.yellow).emojiGlyph, "🟡")
        XCTAssertEqual(IconState.verdict(.red).emojiGlyph, "🔴")
    }

    func testIsTransient() {
        // neutral and working persist until replaced; the rest auto-revert.
        XCTAssertFalse(IconState.neutral.isTransient)
        XCTAssertFalse(IconState.working.isTransient)
        XCTAssertTrue(IconState.empty.isTransient)
        XCTAssertTrue(IconState.tooLong.isTransient)
        XCTAssertTrue(IconState.error.isTransient)
        XCTAssertTrue(IconState.verdict(.green).isTransient)
    }

    func testAllStatesIsExhaustive() {
        // If a case is added without extending allStates, the coverage test in
        // IconFontCoverageTests would silently stop checking it.
        XCTAssertEqual(IconState.allStates.count, 8)
        for state in IconState.allStates {
            XCTAssertFalse(state.glyph.isEmpty)
            XCTAssertFalse(state.emojiGlyph.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd cli && swift test --filter IconStateTests`
Expected: compile failure — `.tooLong`, `tint`, `emojiGlyph`, `allStates` and `IconTint` do not exist yet.

- [ ] **Step 3: Write the implementation**

Replace the whole of `cli/Sources/SpellCheckerCore/IconState.swift`:

```swift
/// Colour applied to the status-item glyph.
///
/// A plain enum rather than an `NSColor` so `SpellCheckerCore` stays free of
/// AppKit; `StatusItemController` in the app target does the mapping. That also
/// makes the whole icon vocabulary swappable from one file.
public enum IconTint: Sendable, Equatable {
    /// The default label colour — follows light/dark appearance.
    case standard
    case green
    case yellow
    case red
    case orange
    /// Dimmed: a state worth noticing but not worth alarm.
    case secondary
}

/// What the menu-bar icon shows. `verdict` wraps the traffic-light result so the
/// three colours share one case; the standalone cases cover the lifecycle.
public enum IconState: Sendable, Equatable {
    case neutral   // idle
    case working   // a check is running
    case empty     // clipboard had no text — nothing to check (NOT an error)
    case tooLong   // clipboard text is past the limit — almost surely a misclick
    case error     // claude failed or returned unparseable output
    case verdict(Verdict)

    /// Nerd Font glyph (JetBrainsMonoNF-Regular), rendered as the status-item
    /// button's attributed title.
    ///
    /// Written as `\u{...}` escapes, **never** as pasted literal characters:
    /// these are private-use codepoints that corrupt when retyped out of a
    /// rendered terminal. The codepoints were chosen by rendering candidates and
    /// looking at them — Nerd Font glyph *names* do not survive the v2 → v3
    /// renumbering. See Findings/nerd-font-codepoint-identity.
    public var glyph: String {
        switch self {
        case .neutral: return "\u{f10c}"  // nf-fa-circle_o — hollow circle
        case .working: return "\u{f252}"  // nf-fa-hourglass_half
        case .empty:   return "\u{f016}"  // nf-fa-file_o — an empty page
        case .tooLong: return "\u{f02d}"  // nf-fa-book — "you copied a book"
        case .error:   return "\u{f071}"  // nf-fa-exclamation_triangle
        case .verdict: return "\u{f111}"  // nf-fa-circle — colour carries the verdict
        }
    }

    /// Colour for `glyph`. `tooLong` is deliberately *not* `error`: "you copied a
    /// whole page" and "claude broke" want different reactions.
    public var tint: IconTint {
        switch self {
        case .neutral, .working: return .standard
        case .empty, .tooLong:   return .secondary
        case .error:             return .orange
        case .verdict(let v):
            switch v {
            case .green:  return .green
            case .yellow: return .yellow
            case .red:    return .red
            }
        }
    }

    /// Shown when the Nerd Font is not installed. Without a fallback, a missing
    /// font leaves an empty box where the app's only UI lives — and that is
    /// exactly the case for anyone installing via Homebrew.
    public var emojiGlyph: String {
        switch self {
        case .neutral: return "⚪"
        case .working: return "⏳"
        case .empty:   return "📋"
        case .tooLong: return "📏"
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
        case .empty, .tooLong, .error, .verdict: return true
        }
    }

    /// Every state, for exhaustive tests. `IconState` cannot be `CaseIterable`
    /// because `verdict` carries an associated value.
    public static let allStates: [IconState] = [
        .neutral, .working, .empty, .tooLong, .error,
        .verdict(.green), .verdict(.yellow), .verdict(.red),
    ]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd cli && swift test --filter IconStateTests`
Expected: **6 tests, all passing.**

- [ ] **Step 5: Confirm nothing else broke**

Run: `cd cli && swift build && swift test`
Expected: the whole suite passes. `StatusItemController` still compiles because it only reads `glyph` — it renders the new codepoints untinted for now, which Task 5 fixes. `ParseVerdictTests.testVerdictDisplay` must still pass unchanged: it asserts `Verdict.red.display == "🔴 red"`, which is the guard that terminal output keeps its emoji.

- [ ] **Step 6: Commit**

```bash
git add cli/Sources/SpellCheckerCore/IconState.swift cli/Tests/SpellCheckerCoreTests/IconStateTests.swift
git commit -m "feat: Nerd Font glyphs and tints for the status icon

Swaps the emoji vocabulary for JetBrainsMono Nerd Font codepoints, adds the
tooLong state, and carries colour as an IconTint enum so Core stays
AppKit-free. Emoji survive as the fallback for machines without the font;
Verdict.display keeps emoji for terminal output."
```

---

### Task 4: Font-coverage test

Codepoints are only useful if the font actually has them. This test guards the choice, and documents the API trap that produced a wrong answer the first time.

**Files:**
- Create: `cli/Tests/SpellCheckerCoreTests/IconFontCoverageTests.swift`

**Interfaces:**
- Consumes: `IconState.allStates` and `IconState.glyph` from Task 3.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the test**

Create `cli/Tests/SpellCheckerCoreTests/IconFontCoverageTests.swift`:

```swift
import AppKit
import CoreText
import XCTest
@testable import SpellCheckerCore

final class IconFontCoverageTests: XCTestCase {
    /// The font StatusItemController asks for. Duplicated as a literal here
    /// because the Bar target is an executable and cannot be imported by tests;
    /// if one changes, change both.
    private static let fontName = "JetBrainsMonoNF-Regular"

    func testFontCoversEveryDeclaredGlyph() throws {
        guard let font = NSFont(name: Self.fontName, size: 15) else {
            throw XCTSkip("\(Self.fontName) is not installed — the app falls back to emoji")
        }

        // CTFontCopyCharacterSet, NOT CTFontGetGlyphsForCharacters: the latter
        // works in UTF-16 code units, so every codepoint above U+FFFF arrives as
        // a surrogate pair and reports "missing" — a false negative that covers
        // the entire Material Design block in Nerd Fonts v3.
        // See Findings/nerd-font-codepoint-identity.
        let covered = CTFontCopyCharacterSet(font as CTFont) as CharacterSet

        for state in IconState.allStates {
            for scalar in state.glyph.unicodeScalars {
                let hex = String(scalar.value, radix: 16, uppercase: true)
                XCTAssertTrue(
                    covered.contains(scalar),
                    "\(Self.fontName) has no glyph for U+\(hex) (\(state))"
                )
            }
        }
    }
}
```

- [ ] **Step 2: Run it**

Run: `cd cli && swift test --filter IconFontCoverageTests`
Expected: **PASS** on this machine — `~/Library/Fonts` has the JetBrainsMono Nerd Font family, and all six codepoints were verified covered during design.

- [ ] **Step 3: Prove the skip path works**

Temporarily change `fontName` to `"NoSuchFont-Regular"`, re-run, and confirm the test reports **skipped** rather than failed. Then change it back and re-run to confirm it passes again. A skip that silently fails to skip is worse than no test.

- [ ] **Step 4: Commit**

```bash
git add cli/Tests/SpellCheckerCoreTests/IconFontCoverageTests.swift
git commit -m "test: assert the Nerd Font covers every icon codepoint

Skips rather than fails when the font is absent, so the suite still passes on
a machine without it. Uses CTFontCopyCharacterSet: CTFontGetGlyphsForCharacters
works in UTF-16 units and false-negatives everything above U+FFFF."
```

---

### Task 5: `StatusItemController` renders the font and tint

**Files:**
- Modify: `cli/Sources/SpellCheckerBar/StatusItemController.swift`

**Interfaces:**
- Consumes: `IconState.glyph`, `IconState.tint`, `IconState.emojiGlyph`, `IconTint` from Task 3.
- Produces: `StatusItemController.show(_:)` and `setMenu(_:)` unchanged in signature — `AppDelegate` and `CheckCoordinator` need no edits for this task.

No unit test: this is an executable target that SwiftPM cannot import into the test bundle, and the behaviour is "does it look right in the menu bar". Task 8 verifies it by eye.

- [ ] **Step 1: Rewrite the controller**

Replace the whole of `cli/Sources/SpellCheckerBar/StatusItemController.swift`:

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

    /// Nerd Font used for the glyphs, by PostScript name. The proportional
    /// variant, not `JetBrainsMonoNFM-Regular`: the Mono variant forces every
    /// glyph into one terminal cell, which squeezes the wide icons.
    /// nil when the font is not installed — see `render(_:)`.
    private static let glyphFont = NSFont(name: "JetBrainsMonoNF-Regular", size: glyphPointSize)

    /// Both values were tuned against the real menu bar; Nerd Font metrics are
    /// built for a terminal cell, so the glyphs need a nudge to sit on the menu
    /// bar's optical centre.
    private static let glyphPointSize: CGFloat = 15
    private static let glyphBaselineOffset: CGFloat = -1

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render(.neutral)
    }

    func setMenu(_ menu: NSMenu) { statusItem.menu = menu }

    /// Render `state`. Any pending revert is cancelled first, so a fresh result
    /// (or a new `.working`) restarts the cycle cleanly.
    func show(_ state: IconState) {
        revertTimer?.invalidate()
        revertTimer = nil
        render(state)
        guard state.isTransient else { return }
        revertTimer = Timer.scheduledTimer(
            withTimeInterval: displayDuration, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.show(.neutral) }
        }
    }

    private func render(_ state: IconState) {
        guard let button = statusItem.button else { return }

        // Without the font the glyphs would render as empty boxes, so fall back
        // to the emoji vocabulary rather than showing nothing at all.
        guard let font = Self.glyphFont else {
            button.attributedTitle = NSAttributedString(string: state.emojiGlyph)
            return
        }

        button.attributedTitle = NSAttributedString(
            string: state.glyph,
            attributes: [
                .font: font,
                .foregroundColor: Self.color(for: state.tint),
                .baselineOffset: Self.glyphBaselineOffset,
            ]
        )
    }

    /// The one place `IconTint` becomes an `NSColor`. `.standard` uses
    /// `labelColor` (not black) so the icon follows light and dark appearance.
    private static func color(for tint: IconTint) -> NSColor {
        switch tint {
        case .standard:  return .labelColor
        case .green:     return .systemGreen
        case .yellow:    return .systemYellow
        case .red:       return .systemRed
        case .orange:    return .systemOrange
        case .secondary: return .secondaryLabelColor
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd cli && swift build`
Expected: clean build. If Swift complains that `glyphPointSize` is used before it is declared in the `glyphFont` initialiser, that is fine at type scope — static properties are lazy — but if it does error, move `glyphPointSize` and `glyphBaselineOffset` above `glyphFont`.

- [ ] **Step 3: Smoke-test from the terminal**

Run: `cd cli && swift run spell-checker-bar`
Expected: a **hollow circle** appears in the menu bar, not ⚪ and not an empty box. Click it → the menu with "Check clipboard now" and "Quit Spell Checker". Copy a clear sentence, choose **Check clipboard now** → hourglass, then a **green filled circle**, reverting to the hollow circle after ~4s. Quit from the menu.

Vertical centring is judged in Task 8 against the bundled app; here you are only confirming the glyphs render and the tints apply.

- [ ] **Step 4: Commit**

```bash
git add cli/Sources/SpellCheckerBar/StatusItemController.swift
git commit -m "feat: render the status icon as a tinted Nerd Font glyph

Maps IconTint to NSColor in the app target, keeping Core AppKit-free, and
falls back to emoji when the font is missing. .standard uses labelColor so the
idle icon follows light and dark appearance."
```

---

### Task 6: `CheckCoordinator` consumes `InputText`

**Files:**
- Modify: `cli/Sources/SpellCheckerBar/CheckCoordinator.swift:18-37`

**Interfaces:**
- Consumes: `InputText.check(_:)` and `InputCheck` from Task 1; `IconState.tooLong` from Task 3.
- Produces: `runCheck()` unchanged in signature.

- [ ] **Step 1: Replace the inline guard with the shared rule**

In `cli/Sources/SpellCheckerBar/CheckCoordinator.swift`, `runCheck()` currently reads:

```swift
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
```

Replace it with:

```swift
    func runCheck() {
        // Ignore re-triggers while a check is in flight — no overlapping runs.
        guard !isChecking else { return }

        let text: String
        switch InputText.check(NSPasteboard.general.string(forType: .string)) {
        case .ok(let trimmed):
            text = trimmed
        case .noText:
            status.show(.empty)    // nothing to check — not an error
            return
        case .tooLong:
            status.show(.tooLong)  // a whole page got copied; don't spend a call on it
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
```

Leave `evaluate(_:_:)` untouched. Note that a non-text clipboard (an image) makes `string(forType:)` return nil, which `InputText.check` already classifies as `.noText` — same behaviour as before.

- [ ] **Step 2: Build**

Run: `cd cli && swift build`
Expected: clean build.

- [ ] **Step 3: Verify both new paths by hand**

Run `cd cli && swift run spell-checker-bar`, then:

```bash
pbcopy </dev/null                              # empty clipboard
# → "Check clipboard now" shows the outlined-page glyph for ~4s. No hourglass.

printf 'a%.0s' $(seq 2001) | pbcopy             # oversized clipboard
# → "Check clipboard now" shows the book glyph INSTANTLY (no hourglass at all).
```

The absence of an hourglass is the real assertion: it proves no `claude` call was made. Quit from the menu when done.

- [ ] **Step 4: Commit**

```bash
git add cli/Sources/SpellCheckerBar/CheckCoordinator.swift
git commit -m "refactor: menu-bar check uses the shared input guard

Empty clipboards keep their own icon; oversized ones now get the book glyph
and are rejected before any claude call, instead of being sent in full."
```

---

### Task 7: Rebind the hotkey to Hyper+C

**Files:**
- Modify: `cli/Sources/SpellCheckerBar/Shortcuts.swift:4-9`

**Interfaces:**
- Consumes: `KeyboardShortcuts` (existing dependency).
- Produces: `KeyboardShortcuts.Name.toggleCheck`, default **⌃⌥⌘C**. The name string `"toggleCheck"` must not change — it is the `UserDefaults` key.

- [ ] **Step 1: Change the default and its comment**

Replace the whole of `cli/Sources/SpellCheckerBar/Shortcuts.swift`:

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global hotkey that triggers a clipboard check. Default: Hyper+C (⌃⌥⌘C).
    ///
    /// Changing this default is enough to rebind: `KeyboardShortcuts` only reads
    /// it when no user-set shortcut is stored in UserDefaults, and nothing in the
    /// app writes one (there is no recorder UI yet — see the vault inbox). The
    /// name string is the UserDefaults key and must stay `"toggleCheck"`.
    /// Slice 3 adds a second name for the translator (⌃⌥⌘⇧C).
    @MainActor static let toggleCheck = Self(
        "toggleCheck",
        default: .init(.c, modifiers: [.control, .option, .command])
    )
}
```

- [ ] **Step 2: Build and verify the new binding works**

Run: `cd cli && swift build && swift run spell-checker-bar`

Copy `Thanks for the review, I've merged the branch.` then press **⌃⌥⌘C**.
Expected: hourglass → green filled circle → hollow circle after ~4s.

- [ ] **Step 3: Verify the old binding is gone**

First make sure no *other* build of this app is running. The main clone at `~/pet/spell-checker` builds to `~/pet/spell-checker/cli/dist/SpellChecker.app`, and that build still binds the old **⌃⌥C** — if it is alive, ⌃⌥C will fire *it* and the rebind will look broken when it is fine. Check with `pgrep -fl SpellChecker` and quit any stray instance from its own menu before testing.

With only this branch's app running, press **⌃⌥C** (no ⌘).
Expected: **nothing happens.** If it still fires, a shortcut was persisted at some point — add a one-time `KeyboardShortcuts.reset(.toggleCheck)` in `AppDelegate.applicationDidFinishLaunching` before the `onKeyDown` registration, run once, then remove it. Do not change the name string to work around this.

Quit from the menu when done.

- [ ] **Step 4: Commit**

```bash
git add cli/Sources/SpellCheckerBar/Shortcuts.swift
git commit -m "feat: rebind the clipboard check to Hyper+C (⌃⌥⌘C)

Makes room for the translator on Hyper+⇧C in slice 3. Changing the code
default is sufficient — nothing persists a user shortcut yet."
```

---

### Task 8: Verify against the real menu bar and tune the glyph metrics

The two numbers in `StatusItemController` — point size and baseline offset — cannot be settled from a rendered PNG. This task is manual, and it is the one that decides whether the icons actually look right.

**Files:**
- Modify (likely): `cli/Sources/SpellCheckerBar/StatusItemController.swift` — `glyphPointSize`, `glyphBaselineOffset`.

- [ ] **Step 1: Build and launch the bundled app**

```bash
# Quit any dev instance first, or you will be looking at two status items.
pkill -f 'SpellChecker.app/Contents/MacOS/SpellChecker' || true
make run-app
```

Expected: `✅ built cli/dist/SpellChecker.app`, then a hollow circle in the menu bar and **no Dock icon**.

- [ ] **Step 2: Judge the vertical centring**

Compare the glyph against the neighbouring menu-bar icons. If it sits high or low, adjust `glyphBaselineOffset` by 0.5 at a time (negative moves it down); if it reads too small or too heavy next to the system icons, adjust `glyphPointSize` by 1. After each change:

```bash
pkill -f 'SpellChecker.app/Contents/MacOS/SpellChecker'
make run-app
```

Stop when it looks deliberate rather than approximately placed.

- [ ] **Step 3: Run the full end-to-end checklist against the bundle**

This is also the `PATH`/TCC regression check — a Finder-launched `.app` does not inherit the shell `PATH`.

| clipboard | press ⌃⌥⌘C | expected |
|---|---|---|
| `Thanks for the review, I've merged the branch.` | ⌃⌥⌘C | hourglass → green circle → hollow circle after ~4s |
| `Please send the file to Anna and her assistant when she is ready.` | ⌃⌥⌘C | hourglass → **red** circle |
| `i has finished the task and it works good now please to review when you has time thanks` | ⌃⌥⌘C | hourglass → **yellow** circle |
| `pbcopy </dev/null` (empty) | ⌃⌥⌘C | outlined page, ~4s, **no hourglass** |
| `printf 'a%.0s' $(seq 2001) \| pbcopy` | ⌃⌥⌘C | **book**, instantly, **no hourglass** |
| any text | ⌃⌥⌘C twice fast | second press ignored while the hourglass shows |

Also confirm: ⌃⌥C alone does nothing; **Quit Spell Checker** terminates the app. If any check shows the warning triangle, `claude` was not found or failed — investigate before continuing, do not tune around it.

- [ ] **Step 4: Verify the emoji fallback in the real app**

Temporarily change the font name in `StatusItemController` to `"NoSuchFont-Regular"`, then `make run-app`. Expected: the emoji icons (⚪ ⏳ 🟢 …) appear instead of empty boxes. Revert the name and rebuild. This is the code path every Homebrew user without the font will hit, and it is invisible until something forces it.

- [ ] **Step 5: Check light and dark appearance**

Toggle System Settings → Appearance. The idle glyph must stay legible in both — that is what `.labelColor` buys, and it is worth confirming once.

- [ ] **Step 6: Commit any tuning**

```bash
git add cli/Sources/SpellCheckerBar/StatusItemController.swift
git commit -m "fix: tune the status glyph size and baseline for the menu bar

Values found by looking at the real menu bar; Nerd Font metrics are built for
a terminal cell, not a status item.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

If Steps 2–5 needed no change, skip this commit and say so in the task report rather than inventing a change.

---

### Task 8b: Migrate a stale ⌃⌥C binding on upgrade

*Added during execution.* Task 8 uncovered that Task 7's rebind was correct but inert: `KeyboardShortcuts.Name(_:default:)` persists its default into `UserDefaults` on first launch (`Name.swift:41-48` — `if let initialShortcut, !userDefaultsContains(name: self) { setShortcut(...) }`), and the stored value wins on every later launch. Editing the code default can never rebind an install that has already run. Both this branch's bundle and the `swift run` dev binary held `{"carbonKeyCode":8,"carbonModifiers":6144}` — ⌃⌥C — and the hotkey only started working after the key was deleted by hand. `UserDefaults` is keyed by bundle identifier, so every build sharing `io.klimov.spellchecker` reads and writes one value. *(Corrected after the final review: an older build re-seeds ⌃⌥C **only when the stored key is absent** — the `!userDefaultsContains` guard means it otherwise just reads whatever is stored and binds that. An earlier version of this paragraph claimed any launch of an older build re-breaks a newer one, which is false.)*

**Files:**
- Create: `cli/Sources/SpellCheckerBar/LegacyShortcutMigration.swift`
- Modify: `cli/Sources/SpellCheckerBar/AppDelegate.swift` — call it before `onKeyDown` registration

**Interfaces:**
- Consumes: `KeyboardShortcuts.getShortcut(for:)`, `KeyboardShortcuts.reset(_:)`, `KeyboardShortcuts.Shortcut(_:modifiers:)`, `KeyboardShortcuts.Name.toggleCheck`.
- Produces: `migrateLegacyToggleCheckShortcutIfNeeded()`, called once at launch.

**Behaviour — narrow on purpose:** set a one-time flag first so the whole thing runs at most once per install; then replace the stored shortcut **only** if it is exactly the old ⌃⌥C. Any other stored value is left alone, so a deliberate rebinding through the Phase 3 recorder UI is never stomped. `reset` is the right call rather than `setShortcut`: it writes the name's current default — whatever `Shortcuts.swift` declares right now — so the migration cannot rot if the default changes again.

**No unit test:** `SpellCheckerBar` is an executable target SwiftPM cannot import. It is verified mechanically instead — the stored value is observable with `defaults read`, so the migration can be proven without looking at anything.

### Task 9: Documentation sweep

Six live documents describe a hotkey and an icon set that no longer exist, and the spec itself has two inaccuracies found while writing this plan.

**Files:**
- Modify: `Makefile:52` (+ a new `test` target), `CLAUDE.md:57-58`, `README.md:23,37`, `cli/README.md:57,60`
- Modify: `spell-checker-vault/Spec.md:24`, `spell-checker-vault/Roadmap.md:25`, `spell-checker-vault/Design/phase2-menubar-evaluator.md`, `spell-checker-vault/Problems/concurrent-recheck-while-busy.md`, `spell-checker-vault/Ideas/inbox.md:8-10`, `spell-checker-vault/Design/ad-hoc-translator.md`
- **Do not modify:** `docs/superpowers/plans/2026-06-25-phase2-menubar-evaluator.md` or anything in `spell-checker-vault/Sessions/` — those record what was true then, and rewriting them would erase the history the vault exists to keep.

- [ ] **Step 1: Update the hotkey and icon legend everywhere it is live**

Work through this list; every location was confirmed by grep:

| file:line | change |
|---|---|
| `Makefile:52` | `hotkey:   ⌃⌥C checks the clipboard` → `⌃⌥⌘C (Hyper+C) checks the clipboard` |
| `CLAUDE.md:57` | `the global hotkey **⌃⌥C**` → `**⌃⌥⌘C** (Hyper+C)` |
| `CLAUDE.md:58` | the `🔴/🟡/🟢 verdict (or ⚠️ / 📋)` sentence → **exact replacement A** below |
| `README.md:23` | `press **⌃⌥C**` → `press **⌃⌥⌘C** (Hyper+C)` |
| `README.md:37` | `a global hotkey (**⌃⌥C**) and shows a 🔴 / 🟡 / 🟢` → **exact replacement B** below |
| `cli/README.md:57` | `Press **⌃⌥C** (Control+Option+C)` → `Press **⌃⌥⌘C** (Control+Option+Command+C, "Hyper+C")` |
| `cli/README.md:60` | the `⚪ idle · ⏳ checking · …` legend → **exact replacement C** below |
| `Spec.md:24` | `(**⌃⌥C** → verdict in the tray icon, …)` → `(**⌃⌥⌘C** → …)` |
| `Roadmap.md:25` | `**⌃⌥C** runs the evaluator` → keep the Phase 2 record but add `(rebound to **⌃⌥⌘C** in Phase 2.3)` so the history stays readable |
| `Problems/concurrent-recheck-while-busy.md:4,8` | ⌃⌥C → ⌃⌥⌘C; the "working ⏳ state" → the hourglass glyph |
| `Ideas/inbox.md:8-10` | the "Shortcut recorder UI" item says the hardcoded default is ⌃⌥C → ⌃⌥⌘C |

In `spell-checker-vault/Design/phase2-menubar-evaluator.md`, update lines 3, 16, 19, 61, 130, 133, 134 (hotkey and emoji mentions) and the icon table at lines 71-79: add the `tooLong` row and replace the emoji column with codepoints. Add one line under the table pointing at `[[0008-nerd-font-status-icons]]` and `[[ad-hoc-translator]]` so a reader knows why it changed.

**Exact replacement text.** The three descriptive lines need real prose, not a substitution, and they must not print the Nerd Font glyphs themselves: GitHub renders both READMEs with a web font that has nothing in the private-use area, so a pasted glyph would show as an empty box to anyone reading the repo online. Name the shapes in words instead.

**A — `CLAUDE.md:58`:**

```markdown
shows the verdict in the status-item icon for ~4s, then reverts: a green / yellow / red dot, an
outlined page when the clipboard has no text, a book when the text is over 2000 characters, or a
warning triangle on failure. The glyphs are JetBrainsMono Nerd Font codepoints tinted via
`IconTint`; without that font installed the app falls back to emoji.
```

**B — `README.md:37`:**

```markdown
menu-bar app that rates the clipboard on a global hotkey (**⌃⌥⌘C**) and shows a green / yellow /
red dot in the menu bar
```

Keep whatever follows on the original line intact — only the hotkey and the emoji list change.

**C — `cli/README.md:60`:**

```markdown
Hollow circle = idle · hourglass = checking · green / yellow / red dot = verdict · outlined page =
clipboard empty · book = text over 2000 characters · warning triangle = error. These are
JetBrainsMono Nerd Font glyphs; install the font (`brew install --cask font-jetbrains-mono-nerd-font`)
or the app falls back to emoji: ⚪ ⏳ 🟢 🟡 🔴 📋 📏 ⚠️.
```

- [ ] **Step 2: Correct two things in the spec itself**

In `spell-checker-vault/Design/ad-hoc-translator.md`:

1. The "Docs to update in the same commit" line (≈146) claims only `CLAUDE.md`, `Spec.md` and the Phase 2 design note name the old hotkey. It missed `README.md`, `cli/README.md`, `Makefile`, `Roadmap.md`, `Problems/concurrent-recheck-while-busy.md` and `Ideas/inbox.md`. Replace it with the full list.
2. The layering paragraph names the neutral tint `.none`; the implementation uses **`.standard`** to avoid reading as `Optional.none`. Update the enum listing.
3. Nothing in the spec says it, but add a line to the Slice 1 section recording what execution taught: files in `SpellCheckerCore` declare their own `import Foundation` when they use Foundation APIs. Swift imports are file-scoped; relying on a sibling file's import compiles today (debug and release alike) but is undefined by contract. The rule the design cares about is narrower than "import nothing" — it is **no UI frameworks in Core**.
4. **The rebind-safety claim is false and must be rewritten.** The design note currently says: *"The rebind is safe: `KeyboardShortcuts.Name(_:default:)` only consults the code default when no user shortcut is stored in `UserDefaults`, and nothing in the app writes one."* The first half is right; the second is wrong. The library's own `Name.swift` init writes the default into `UserDefaults` on first launch, so after any version's first run the stored value wins permanently. Editing the code default cannot rebind an install that has already run — which is why Task 8b exists. Say so, and mention that `UserDefaults` is keyed by **bundle identifier**, so every build sharing `io.klimov.spellchecker` competes for one value.
5. **The icon table's tints are out of date.** `empty` and `tooLong` are no longer dimmed — the user found `secondaryLabelColor` too faint to read in a real menu bar, so both are full-contrast now and `IconTint.secondary` is gone (commit `f9fdd1a`). What distinguishes them from a verdict is the glyph shape, not a dimmer colour. Update the table in the design note and the `IconTint` case list.
6. **Add Task 8b's migration to the design note** — one short paragraph under the hotkey section: on launch the app replaces a stored shortcut that is exactly the legacy ⌃⌥C with the current default, once, guarded by the `migratedToggleCheckToHyperC` flag, so a deliberate rebinding via the Phase 3 recorder UI is never overridden.

**Step 2b: write a vault Finding for the persisted-shortcut trap**

Create `spell-checker-vault/Findings/keyboardshortcuts-persists-its-default.md`, in the style of the existing Findings notes (a dated "what happened" narrative, then the takeaway, then Related wikilinks). It must record: that the rebind looked correct and did nothing; that Karabiner was the first and **wrong** suspect, refuted by a Karabiner-EventViewer dump showing `c` arriving with flags `left_control, left_option, left_command`; that `defaults read io.klimov.spellchecker` then showed `{"carbonKeyCode":8,"carbonModifiers":6144}` — 6144 being `controlKey (4096) + optionKey (2048)` with no `cmdKey (256)`; the `Name.swift` init that causes it; that the domain is shared by bundle identifier, so an older build re-seeds ⌃⌥C **only when the stored key is absent** (with a value present it reads and binds that value instead); and the takeaway that a code-default change is not a rebind, plus the diagnostic worth reaching for first (`defaults read <bundle-id>`, and decoding carbon modifier masks). Link it from `Home.md`'s Findings line and from [[ad-hoc-translator]].

**Step 2c: tidy one truncated comment**

`cli/Sources/SpellCheckerBar/LegacyShortcutMigration.swift` has a comment ending "...even if a later step changes." — the sentence has no object and reads as a dropped word. Complete the thought (it means: even if a later step in this function returns early or is modified in future). Comment text only; change no code.

- [ ] **Step 3: Add a `make test` target**

Every task in this plan runs `swift test` by hand, and the Makefile is the documented entry point for everything else. In `Makefile`, add `test` to the `.PHONY` list, a help line, and:

```makefile
test:
	cd $(PKGDIR) && swift test
```

Put the help line after `make build` so the ordering stays build → test → install.

- [ ] **Step 4: Verify the docs match reality**

```bash
# No live document should still name the old hotkey. Only the completed Phase 2
# plan and the session logs may, and they are excluded here.
grep -rn "⌃⌥C" --include='*.md' --include='Makefile' . \
  | grep -v '\.build' \
  | grep -v 'docs/superpowers/plans/2026-06-25' \
  | grep -v 'spell-checker-vault/Sessions/' \
  | grep -v '⌃⌥⌘C'
# Expected: no output, or only lines that deliberately describe the old binding
# as history (e.g. Roadmap's "rebound to ⌃⌥⌘C").

make test        # the new target works
make help        # lists it
```

- [ ] **Step 5: Commit**

```bash
git add Makefile CLAUDE.md README.md cli/README.md spell-checker-vault
git commit -m "docs: Hyper+C and the Nerd Font icon set

Updates every live document that named ⌃⌥C or the emoji vocabulary, and
corrects two things in the slice design: the docs-to-update list missed four
files, and the neutral tint is .standard rather than .none. Leaves the
completed Phase 2 plan and the session logs alone — they record what was true
then. Adds make test, which this slice leaned on throughout.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Slice 1 Definition of Done

- `cd cli && swift test` passes; `InputTextTests`, `IconStateTests` and `IconFontCoverageTests` all green (the last may legitimately skip on a machine without the font).
- `make build`, `make test`, `make app` all succeed.
- The bundled app shows tinted Nerd Font glyphs, correctly centred, in both light and dark appearance.
- ⌃⌥⌘C checks the clipboard; ⌃⌥C does nothing.
- An empty clipboard shows the outlined page; a 2001-character clipboard shows the book **instantly**, proving no LLM call.
- `spell-checker check` still returns one verdict, and exits 2 with a numbered message on oversized input.
- No live document names ⌃⌥C or the emoji icon set; the Phase 2 plan and session logs are untouched.

## Not in this slice

`spell-checker translate`, the `ClaudeCLI` extraction, `TextTranslator`, the floating `NSPanel`, the translating icon state (`U+F05CA`), and cancellation. Those are slices 2 and 3 of `spell-checker-vault/Design/ad-hoc-translator.md` and get their own plans.
