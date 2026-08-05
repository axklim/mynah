# Translator Slice 3 — The Floating Window

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hyper+⇧C translates the clipboard into a floating window that dismisses on Esc or focus loss, and kills the in-flight `claude` call when it does.

**Architecture:** The pure parts move to the existing `SpellCheckerUI` library, which the test bundle already depends on — the view-state mapping and every user-facing sentence become tested functions instead of untestable code inside an executable. `SpellCheckerBar` keeps only what genuinely needs AppKit lifecycle: the `NSPanel` subclass and the coordinator. Cancellation is threaded from the panel down to the subprocess through a new public `TranslationHandle`, so the backend-swap protocol never mentions `Process`.

**Tech Stack:** Swift 6, SwiftPM (no Xcode project), SwiftUI + AppKit, XCTest, `KeyboardShortcuts`, `make`.

**Spec:** `spell-checker-vault/Design/ad-hoc-translator.md`, the "Slice 3" section — **the authority on behaviour**. If implementation diverges, the note gets corrected, because the vault is this project's source of truth. Slices 1 and 2 are on `main` (`e141393`, `033b7ec`).

## Global Constraints

- **Branch:** `translator-slice-3`, already created from `main` at `033b7ec`. Never commit to `main`. Never `git commit --amend`, never rewrite history. Do not push.
- **Commit titles:** plain descriptive, **no ticket prefix** (repo is under `~/pet`). **Every commit message must end with** `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- **Swift 6**, platform floor **macOS 13**. **No new package dependencies** — SwiftUI ships with the CLT SDK.
- **`SpellCheckerCore` contains no AppKit and no SwiftUI.** `SpellCheckerUI` may import both. SwiftUI views live in `SpellCheckerUI`; AppKit window lifecycle lives in `SpellCheckerBar`.
- **Every file imports exactly what it uses.** Swift imports are file-scoped; slice 1 shipped a file that compiled only because a sibling's import leaked across the module.
- **The public API must not mention `Foundation.Process`.** `TextTranslator` is the documented backend-swap point (Decision 0006), and a future litellm/HTTP backend cancels an HTTP task, not a subprocess — leaking `Process` would make such a backend unable to conform meaningfully.
- **The 2000-character limit is not re-implemented.** `InputText.check` already exists; the translator reuses it, and `.ok` carries the trimmed text.
- **Tests:** XCTest in `cli/Tests/SpellCheckerCoreTests/` (that target already depends on both `SpellCheckerCore` and `SpellCheckerUI`). Run with `make test`. The suite is at **41 tests** before this slice.
- **Real `claude` calls cost money and take seconds.** Manual steps name exactly which to make; do not add more and do not loop.

---

## File Structure

**Create in `SpellCheckerCore`** (pure, no UI frameworks):
- `TranslationHandle.swift` — a public cancellation handle. Hides how the work is cancelled.

**Create in `SpellCheckerUI`** (may import SwiftUI/AppKit; **reachable by tests**):
- `TranslationViewState.swift` — the view state plus the pure mapping from a `TranslationResult` or an `InputCheck` rejection. Every user-facing sentence lives here.
- `TranslationView.swift` — the SwiftUI view rendering that state.

**Create in `SpellCheckerBar`** (executable; **not** reachable by tests):
- `TranslationPanel.swift` — the `NSPanel` subclass: Esc, focus loss, placement.
- `TranslateCoordinator.swift` — one translation: guard, clipboard, cancellation, generation counter.
- `Clipboard.swift` — `clipboardText()`, shared by both coordinators.

**Modify:**
- `SpellCheckerCore/IconState.swift` — add `.translating`, extend `allStates`.
- `SpellCheckerCore/TextTranslator.swift` — protocol gains `onStart:`; an extension keeps the one-argument form.
- `SpellCheckerCore/ClaudeCLITranslator.swift` — forward `onStart`, wrapping the `Process` in a handle.
- `SpellCheckerBar/Shortcuts.swift` — add `translateClipboard`.
- `SpellCheckerBar/AppDelegate.swift` — second hotkey, second menu item, wiring.
- `SpellCheckerBar/CheckCoordinator.swift` — use the shared `clipboardText()`.
- `Tests/SpellCheckerCoreTests/IconStateTests.swift` — the new state, and the hardcoded count.
- Docs and vault (final task).

**Why the split matters.** Slice 1's final review found a real defect caused by presentation logic sitting where SwiftPM cannot import it: the mapping that distinguished a green verdict from a red one had no test, so a swapped case would have shipped green. Everything in this slice that can be a pure function is one, in a library the test bundle already links.

---

### Task 1: `IconState.translating`

**Files:**
- Modify: `cli/Sources/SpellCheckerCore/IconState.swift`
- Test: `cli/Tests/SpellCheckerCoreTests/IconStateTests.swift`

**Interfaces:**
- Produces: `IconState.translating`, glyph `"\u{f05ca}"`, tint `.standard`, transient, and present in `allStates` (which becomes 9 entries).

The ledger flagged this precisely: `allStates` is hand-maintained and its test asserts a hardcoded count, so adding a case without extending the array leaves the font-coverage test silently skipping the new glyph. `U+F05CA` is above U+FFFF — exactly the class of codepoint `Findings/nerd-font-codepoint-identity` says must be coverage-checked, because `CTFontGetGlyphsForCharacters` false-negatives there.

- [ ] **Step 1: Update the tests first**

In `IconStateTests.swift`, add to `testGlyphs()`:

```swift
        XCTAssertEqual(IconState.translating.glyph, "\u{f05ca}")   // 文A translate
```

Add to `testTints()`:

```swift
        XCTAssertEqual(IconState.translating.tint, .standard)
```

Add to `testEmojiFallback()`:

```swift
        XCTAssertEqual(IconState.translating.emojiGlyph, "🔤")
```

Add to `testIsTransient()`:

```swift
        XCTAssertTrue(IconState.translating.isTransient)
```

And change the count in `testAllStatesIsExhaustive()` from `8` to `9`:

```swift
        XCTAssertEqual(IconState.allStates.count, 9)
```

- [ ] **Step 2: Run and watch it fail**

Run: `cd cli && swift test --filter IconStateTests`
Expected: compile failure — `type 'IconState' has no member 'translating'`.

- [ ] **Step 3: Add the case**

In `IconState.swift`, add the case to the enum declaration after `error`:

```swift
    case translating  // a translation is in flight; the panel is the real UI
```

Add to `glyph`:

```swift
        case .translating: return "\u{f05ca}"  // nf-md-translate — 文A
```

Add to `tint`, alongside the other untinted states — change the existing `case .neutral, .working:` arm to include it:

```swift
        case .neutral, .working, .translating: return .standard
```

Add to `emojiGlyph`:

```swift
        case .translating: return "🔤"
```

Add to `isTransient` — it belongs with the auto-reverting states:

```swift
        case .empty, .tooLong, .error, .verdict, .translating: return true
```

And extend `allStates`:

```swift
    public static let allStates: [IconState] = [
        .neutral, .working, .empty, .tooLong, .error, .translating,
        .verdict(.green), .verdict(.yellow), .verdict(.red),
    ]
```

Deliberately **not** `.working`: the icon should say *which* of the two hotkeys was pressed.

- [ ] **Step 4: Run the tests**

Run: `cd cli && swift test --filter IconStateTests`
Expected: **6 tests passing** (the same six methods, now with more assertions each).

- [ ] **Step 5: Confirm the font actually has the glyph**

Run: `cd cli && swift test --filter IconFontCoverageTests`
Expected: **PASS, not skipped.** That test iterates `allStates`, so it now checks `U+F05CA` automatically — which is the whole reason Step 1 extended the array. If it fails, the codepoint is wrong; do not "fix" it by changing the test.

- [ ] **Step 6: Whole suite**

Run: `make test`
Expected: **41 tests, 0 failures** — unchanged, because this task added assertions rather than test methods.

- [ ] **Step 7: Commit**

```bash
git add cli/Sources/SpellCheckerCore/IconState.swift cli/Tests/SpellCheckerCoreTests/IconStateTests.swift
git commit -m "feat: add the translating icon state (U+F05CA)

The icon should say which hotkey was pressed, so a translation in flight gets the
文A glyph rather than reusing the checker's hourglass. Extends allStates and its
hardcoded count, without which the font-coverage test would silently skip the new
codepoint — and U+F05CA is above U+FFFF, exactly the range that needs checking.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `TranslationHandle` and threading cancellation

This is the carry-forward slice 2's final review identified: the `onStart` hook exists on `ClaudeCLI.run`, but `ClaudeCLI` is `internal` **and** neither public entry point forwards it, so nothing outside Core can reach it. Cancellation is not solved yet; this task solves it.

**Files:**
- Create: `cli/Sources/SpellCheckerCore/TranslationHandle.swift`
- Create: `cli/Tests/SpellCheckerCoreTests/TranslationHandleTests.swift`
- Modify: `cli/Sources/SpellCheckerCore/TextTranslator.swift`, `cli/Sources/SpellCheckerCore/ClaudeCLITranslator.swift`

**Interfaces:**
- Produces: `public final class TranslationHandle` with `public init(onCancel: @escaping @Sendable () -> Void)` and `public func cancel()`; `TextTranslator.translate(_:onStart:)` with `onStart: (@Sendable (TranslationHandle) -> Void)?`; an extension providing `translate(_:)` unchanged for existing callers (the CLI calls that form and **must not need editing**).

- [ ] **Step 1: Write the failing handle tests**

Create `cli/Tests/SpellCheckerCoreTests/TranslationHandleTests.swift`:

```swift
import XCTest
@testable import SpellCheckerCore

final class TranslationHandleTests: XCTestCase {
    func testCancelRunsTheAction() {
        var cancelled = false
        let handle = TranslationHandle { cancelled = true }
        handle.cancel()
        XCTAssertTrue(cancelled)
    }

    func testCancelIsIdempotent() {
        // The panel can be dismissed twice (Esc, then focus loss as the app hides),
        // and terminating an already-reaped process must not be attempted twice.
        var count = 0
        let handle = TranslationHandle { count += 1 }
        handle.cancel()
        handle.cancel()
        handle.cancel()
        XCTAssertEqual(count, 1)
    }

    func testNotCancellingRunsNothing() {
        var cancelled = false
        _ = TranslationHandle { cancelled = true }
        XCTAssertFalse(cancelled)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `cd cli && swift test --filter TranslationHandleTests`
Expected: compile failure, `cannot find 'TranslationHandle' in scope`.

- [ ] **Step 3: Write the handle**

Create `cli/Sources/SpellCheckerCore/TranslationHandle.swift`:

```swift
import Foundation

/// A cancellation handle for work already in flight.
///
/// Deliberately says nothing about *how* the work is cancelled. `TextTranslator`
/// is the documented backend-swap point (Decision 0006): today the backend is a
/// `claude` subprocess and cancelling means terminating it, but a litellm or HTTP
/// backend would cancel a request instead. A protocol that handed out a
/// `Foundation.Process` could not be implemented by such a backend at all.
///
/// `cancel()` is idempotent: the panel can be dismissed twice in quick succession
/// (Esc, then focus loss as the app hides), and terminating a reaped process twice
/// is not something callers should have to guard against.
public final class TranslationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?

    public init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        lock.lock()
        let action = onCancel
        onCancel = nil
        lock.unlock()
        action?()
    }
}
```

`@unchecked Sendable` with an `NSLock` rather than an actor, because `cancel()` is called from the main actor while the work runs on a background task, and an `async` cancel would force every call site into a `Task` — which is exactly the kind of indirection that made cancellation unreliable in the first place.

- [ ] **Step 4: Run the handle tests**

Run: `cd cli && swift test --filter TranslationHandleTests`
Expected: **3 tests passing.**

- [ ] **Step 5: Thread `onStart` through the protocol**

In `TextTranslator.swift`, replace the protocol declaration with:

```swift
/// The second backend-swap point, beside `TextEvaluator` (Decision 0006).
/// Today: `ClaudeCLITranslator`. A litellm / Gemini backend can conform later
/// without touching the CLI or the panel.
public protocol TextTranslator: Sendable {
    /// Translate English into Russian. The shape of the result follows
    /// `TranslationMode.forInput(text)`.
    ///
    /// - Parameter onStart: called once the work is under way, with a handle that
    ///   cancels it. Invoked on whatever thread the translation runs on, so a
    ///   main-actor caller must hop before touching UI state. The floating window
    ///   uses this to kill an in-flight call when it is dismissed.
    func translate(
        _ text: String,
        onStart: (@Sendable (TranslationHandle) -> Void)?
    ) throws -> TranslationResult
}

public extension TextTranslator {
    /// Translate without taking a cancellation handle — the CLI's case, where the
    /// process lives exactly as long as the command does.
    func translate(_ text: String) throws -> TranslationResult {
        try translate(text, onStart: nil)
    }
}
```

`TextTranslator.swift` still needs **no import**: `TranslationHandle` is in the same module and nothing here touches Foundation.

- [ ] **Step 6: Forward it from `ClaudeCLITranslator`**

In `ClaudeCLITranslator.swift`, change the signature and both branches. `ClaudeCLI.run`'s own hook is `Process`-shaped and stays that way — internal, and correct at that layer. This method is where a process becomes a handle:

```swift
    public func translate(
        _ text: String,
        onStart: (@Sendable (TranslationHandle) -> Void)?
    ) throws -> TranslationResult {
        // ClaudeCLI speaks Process because that is what it owns; the handle is what
        // the public API speaks, so no caller outside Core learns how cancelling works.
        let hook: ((Process) -> Void)? = onStart.map { report in
            { process in
                report(TranslationHandle { process.terminate() })
            }
        }

        switch TranslationMode.forInput(text) {
        case .text:
            let reply = try ClaudeCLI.run(
                prompt: textTranslationPrompt + "\n\n" + text,
                model: model,
                onStart: hook
            )
            let translation = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translation.isEmpty else {
                throw TranslationError(description: "model returned an empty translation")
            }
            return .text(translation)

        case .word:
            let reply = try ClaudeCLI.run(
                prompt: wordTranslationPrompt + "\n\n" + text,
                model: model,
                onStart: hook
            )
            return try Self.parseWordResult(from: reply)
        }
    }
```

- [ ] **Step 7: Verify nothing else needed changing**

Run: `make test`
Expected: **44 tests, 0 failures** (41 + 3). The CLI's `main.swift` calls `translate(source)` and must still compile untouched — the extension covers it. If the build complains about `main.swift`, stop and report rather than editing it: the extension is meant to make that unnecessary, and a failure there means the design is wrong.

Also confirm the build is clean: `cd cli && swift build`.

- [ ] **Step 8: Commit**

```bash
git add cli/Sources/SpellCheckerCore/TranslationHandle.swift cli/Sources/SpellCheckerCore/TextTranslator.swift cli/Sources/SpellCheckerCore/ClaudeCLITranslator.swift cli/Tests/SpellCheckerCoreTests/TranslationHandleTests.swift
git commit -m "feat: make an in-flight translation cancellable

Slice 2 added an onStart hook to ClaudeCLI, but ClaudeCLI is internal and no
public entry point forwarded it, so nothing outside Core could cancel anything.
The protocol now takes onStart and hands back a TranslationHandle rather than a
Process: TextTranslator is the backend-swap point, and an HTTP backend cancels a
request, not a subprocess. An extension keeps the one-argument form the CLI uses.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `TranslationViewState` and every user-facing sentence

**Files:**
- Create: `cli/Sources/SpellCheckerUI/TranslationViewState.swift`
- Create: `cli/Tests/SpellCheckerCoreTests/TranslationViewStateTests.swift`

**Interfaces:**
- Consumes: `TranslationResult`, `WordMeaning`, `InputCheck`, `InputText.characterLimit` from Core.
- Produces: `TranslationViewState` (`.loading` / `.text(String)` / `.word(source: String, meanings: [WordMeaning], hasMore: Bool)` / `.failed(String)`), `TranslationViewState.from(_ result: TranslationResult, source: String) -> TranslationViewState`, and `TranslationViewState.rejection(_ check: InputCheck) -> TranslationViewState?`.

This task exists because of slice 1's lesson: put the mapping and the copy somewhere a test can reach. `SpellCheckerUI` is already a dependency of the test target.

- [ ] **Step 1: Write the failing tests**

Create `cli/Tests/SpellCheckerCoreTests/TranslationViewStateTests.swift`:

```swift
import XCTest
import SpellCheckerCore
@testable import SpellCheckerUI

final class TranslationViewStateTests: XCTestCase {
    func testTextResultBecomesTextState() {
        let state = TranslationViewState.from(.text("Привет, мир."), source: "Hello, world.")
        guard case .text(let russian) = state else { return XCTFail("expected .text, got \(state)") }
        XCTAssertEqual(russian, "Привет, мир.")
    }

    func testWordResultCarriesTheSourceAsHeader() {
        // The source word is the header, so the panel shows what you looked up.
        let meaning = WordMeaning(translation: "фиксация", explanation: "a saved change", example: "One commit per fix.")
        let state = TranslationViewState.from(.word(meanings: [meaning], hasMore: true), source: "commit")
        guard case .word(let source, let meanings, let hasMore) = state else {
            return XCTFail("expected .word, got \(state)")
        }
        XCTAssertEqual(source, "commit")
        XCTAssertEqual(meanings, [meaning])
        XCTAssertTrue(hasMore)
    }

    func testNoTextRejectionReadsAsASentence() {
        guard case .failed(let message)? = TranslationViewState.rejection(.noText) else {
            return XCTFail("expected a rejection state for .noText")
        }
        XCTAssertEqual(message, "Nothing to translate — the clipboard has no text.")
    }

    func testTooLongRejectionNamesBothNumbers() {
        // Naming the count and the limit is what tells the user whether the paste
        // or the limit is the problem.
        guard case .failed(let message)? = TranslationViewState.rejection(.tooLong(count: 4820)) else {
            return XCTFail("expected a rejection state for .tooLong")
        }
        XCTAssertTrue(message.contains("4820"), "missing the count: \(message)")
        XCTAssertTrue(message.contains("\(InputText.characterLimit)"), "missing the limit: \(message)")
    }

    func testOkIsNotARejection() {
        XCTAssertNil(TranslationViewState.rejection(.ok("fine")))
    }

    func testFailureMessageWrapsAnUnderlyingError() {
        struct Boom: Error, CustomStringConvertible { let description = "socket closed" }
        guard case .failed(let message) = TranslationViewState.failure(Boom()) else {
            return XCTFail("expected .failed")
        }
        XCTAssertTrue(message.hasPrefix("Couldn't reach claude."), "wrong lead: \(message)")
        XCTAssertTrue(message.contains("socket closed"), "detail dropped: \(message)")
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `cd cli && swift test --filter TranslationViewStateTests`
Expected: compile failure, `cannot find 'TranslationViewState' in scope`.

- [ ] **Step 3: Write it**

Create `cli/Sources/SpellCheckerUI/TranslationViewState.swift`:

```swift
import SpellCheckerCore

/// What the floating translation window is showing.
///
/// This lives in `SpellCheckerUI` rather than in the app target on purpose: the
/// mapping and every user-facing sentence are pure functions, and an executable
/// target cannot be imported by the test bundle. Slice 1 shipped a real defect of
/// exactly that shape — the mapping that told a green verdict from a red one had
/// no test, so a swapped case would have looked fine.
public enum TranslationViewState: Sendable, Equatable {
    /// The 文A glyph and "Translating…", while the call is in flight.
    case loading
    /// Prose mode: the Russian alone. The English was copied a second ago;
    /// reprinting it is noise.
    case text(String)
    /// Word mode: the source as a header, then up to three meanings.
    case word(source: String, meanings: [WordMeaning], hasMore: Bool)
    /// A guard rejection or a backend failure, phrased as a sentence.
    case failed(String)

    /// Map a finished translation onto the view.
    public static func from(_ result: TranslationResult, source: String) -> TranslationViewState {
        switch result {
        case .text(let russian):
            return .text(russian)
        case .word(let meanings, let hasMore):
            return .word(source: source, meanings: meanings, hasMore: hasMore)
        }
    }

    /// Map an input rejection onto the view, or nil when the input was fine.
    ///
    /// The translator reports rejections **in the window**, never in the menu-bar
    /// icon — the panel is its UI, and an icon that blinked while no window opened
    /// would be a worse explanation than none.
    public static func rejection(_ check: InputCheck) -> TranslationViewState? {
        switch check {
        case .ok:
            return nil
        case .noText:
            return .failed("Nothing to translate — the clipboard has no text.")
        case .tooLong(let count):
            return .failed(
                "That's \(count) characters, over the \(InputText.characterLimit) limit — "
                    + "did you mean to copy that much?"
            )
        }
    }

    /// Map a backend failure onto the view. The detail is kept: "it didn't work"
    /// with no reason is the least useful thing an error can say.
    public static func failure(_ error: Error) -> TranslationViewState {
        .failed("Couldn't reach claude. \(error)")
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd cli && swift test --filter TranslationViewStateTests`
Expected: **6 tests passing.**

- [ ] **Step 5: Whole suite**

Run: `make test`
Expected: **51 tests, 0 failures** (45 + 6 — the suite is at 45, not 44, because Task 2's fix round added a concurrency test).

- [ ] **Step 6: Commit**

```bash
git add cli/Sources/SpellCheckerUI/TranslationViewState.swift cli/Tests/SpellCheckerCoreTests/TranslationViewStateTests.swift
git commit -m "feat: add TranslationViewState with tested user-facing copy

The mapping and every sentence the window can show live in SpellCheckerUI, which
the test bundle already links — an executable target cannot be imported, and slice
1 shipped a defect of exactly that shape. Rejections read as sentences and name
both numbers, so the user can tell whether the paste or the limit is wrong.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `TranslationView` — the SwiftUI content

**Files:**
- Create: `cli/Sources/SpellCheckerUI/TranslationView.swift`

**Interfaces:**
- Consumes: `TranslationViewState`, `WordMeaning`.
- Produces: `public struct TranslationView: View` with `public init(state: TranslationViewState)`, and `public enum TranslationPanelMetrics { public static let width: CGFloat = 420; public static let maxHeight: CGFloat = 520 }` — the panel in Task 5 uses those numbers, so they live beside the view that honours them.

No unit test: a SwiftUI view's rendering is judged by eye, and Task 8 does that. The *state* it renders is already tested, which is the point of Task 3. Do not add a snapshot-testing dependency.

- [ ] **Step 1: Write the view**

Create `cli/Sources/SpellCheckerUI/TranslationView.swift`:

```swift
import SwiftUI
import SpellCheckerCore

/// Sizes shared by the view and the panel that hosts it.
///
/// Starting points to be judged on screen, like the status icon's baseline nudge:
/// 420pt is wide enough for a Russian sentence without becoming a paragraph, and
/// the height cap is what keeps 2000 characters of translation from running off
/// the bottom of the display.
public enum TranslationPanelMetrics {
    public static let width: CGFloat = 420
    public static let maxHeight: CGFloat = 520
}

/// The floating window's content.
public struct TranslationView: View {
    private let state: TranslationViewState

    public init(state: TranslationViewState) {
        self.state = state
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        // Body text is the system font: the Nerd Font is for icon glyphs only.
        .font(.body)
        // Settles the copy question without a button — ⌘C works on a selection.
        .textSelection(.enabled)
        .frame(width: TranslationPanelMetrics.width)
        .frame(maxHeight: TranslationPanelMetrics.maxHeight)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                Text(IconState.translating.glyph)
                    .font(.custom(IconFont.postScriptName, size: 15))
                Text("Translating…")
                    .foregroundStyle(.secondary)
            }

        case .text(let russian):
            Text(russian)
                .textSelection(.enabled)

        case .word(let source, let meanings, let hasMore):
            Text(source)
                .font(.title3.weight(.semibold))
            ForEach(Array(meanings.enumerated()), id: \.offset) { index, meaning in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(index + 1). \(meaning.translation)")
                        .font(.body.weight(.medium))
                    Text(meaning.explanation)
                        .foregroundStyle(.secondary)
                    Text("\u{201C}\(meaning.example)\u{201D}")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            if hasMore {
                Text("more meanings exist")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

        case .failed(let message):
            Text(message)
        }
    }
}
```

Note the loading row uses `IconFont.postScriptName` and `IconState.translating.glyph` from Core rather than repeating either — the font name was already deduplicated once in slice 1 after a review found two copies held together only by a comment.

- [ ] **Step 2: Build**

Run: `cd cli && swift build`
Expected: clean, no warnings. This is the first SwiftUI in the project, so a failure here is most likely a missing `import SwiftUI` or an availability problem against the macOS 13 floor. `.foregroundStyle(.tertiary)` and `.textSelection` are both macOS 12+, so they are fine; if the compiler disagrees, report rather than silently lowering the target.

- [ ] **Step 3: Confirm the suite is untouched**

Run: `make test`
Expected: **51 tests, 0 failures** — this task adds no tests.

- [ ] **Step 4: Commit**

```bash
git add cli/Sources/SpellCheckerUI/TranslationView.swift
git commit -m "feat: add the floating window's SwiftUI content

Word mode gets a header, numbered meanings and a conditional footer; prose mode
gets the Russian alone. System font for body text, selection enabled so ⌘C works
with no copy button, and the loading row reuses IconState.translating and
IconFont.postScriptName rather than repeating either.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `TranslationPanel` — the window itself

**Files:**
- Create: `cli/Sources/SpellCheckerBar/TranslationPanel.swift`

**Interfaces:**
- Consumes: `TranslationView`, `TranslationPanelMetrics`, `TranslationViewState`.
- Produces: `@MainActor final class TranslationPanel` with `init(onDismiss: @escaping () -> Void)`, `func show(_ state: TranslationViewState)`, and `func update(_ state: TranslationViewState)`.

Note there is deliberately **no** public `dismiss()`. Dismissal is always initiated by the user — Esc or focus loss — and the panel reports it upward through `onDismiss`. Nothing in this slice needs to close the window programmatically, and an unused method would be exactly the speculative API a reviewer should object to.

No unit test: `SpellCheckerBar` is an executable target SwiftPM cannot import, and this class is AppKit window lifecycle — activation, key status, screen placement — which is exactly what only a human at a keyboard can judge. Task 8 verifies it. Do not invent a test double for `NSApp`.

- [ ] **Step 1: Write the panel**

Create `cli/Sources/SpellCheckerBar/TranslationPanel.swift`:

```swift
import AppKit
import SwiftUI
import SpellCheckerUI

/// The floating translation window.
///
/// Dismissal is two mechanisms because it is two different events: Esc arrives as
/// `cancelOperation(_:)` and needs the panel to be key, which is why `show` calls
/// `NSApp.activate`; clicking into another app is `hidesOnDeactivate`, and losing
/// key inside this app is the `didResignKey` observer.
@MainActor
final class TranslationPanel {
    private let onDismiss: () -> Void
    private var panel: KeyPanel?

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    /// Show the panel, creating it if needed, and make it key so Esc arrives.
    ///
    /// Reuses an open panel rather than stacking a second one: pressing the hotkey
    /// while a result is on screen replaces the contents.
    func show(_ state: TranslationViewState) {
        let panel = panel ?? makePanel()
        self.panel = panel
        render(state, into: panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Swap the content of an already-visible panel. Does nothing if it is closed,
    /// so a late reply cannot resurrect a dismissed window.
    func update(_ state: TranslationViewState) {
        guard let panel, panel.isVisible else { return }
        render(state, into: panel)
    }

    /// Host the state and size the window to what it actually needs.
    ///
    /// **Why the explicit sizing.** A `ScrollView` does not shrink to its content the
    /// way a `VStack` does, so without this the panel would open at its full
    /// `maxHeight` for every state — a one-line Russian sentence in a 420×520 window
    /// with most of it empty. The panel therefore asks the hosting view what it wants
    /// (`fittingSize`) and clamps the answer: never taller than `maxHeight`, and never
    /// so short that the loading row has nowhere to sit.
    private func render(_ state: TranslationViewState, into panel: KeyPanel) {
        let host = NSHostingView(rootView: TranslationView(state: state))
        panel.contentView = host
        let wanted = host.fittingSize.height
        let height = min(max(wanted, Self.minContentHeight), TranslationPanelMetrics.maxHeight)
        panel.setContentSize(NSSize(width: TranslationPanelMetrics.width, height: height))
        position(panel)
    }

    /// Enough for the loading row plus padding, so a short state still reads as a
    /// window rather than a sliver.
    private static let minContentHeight: CGFloat = 72

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(
            // Initial size only; `render` resizes to the content before it is shown.
            contentRect: NSRect(
                x: 0, y: 0,
                width: TranslationPanelMetrics.width,
                height: Self.minContentHeight
            ),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.onCancelOrResignKey = { [weak self] in self?.handleDismissal() }
        return panel
    }

    private func handleDismissal() {
        panel?.close()
        // Hand focus back to whatever the developer was reading. Two lines either
        // way, and judged by feel in the manual pass.
        NSApp.hide(nil)
        onDismiss()
    }

    /// Horizontally centred on the active screen, in the upper third —
    /// Spotlight-like and predictable, rather than chasing a mouse that had nothing
    /// to do with pressing a keyboard shortcut.
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.maxY - visible.height / 3 - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// An `NSPanel` that reports Esc and loss of key status to its owner.
@MainActor
final class KeyPanel: NSPanel {
    var onCancelOrResignKey: (() -> Void)?

    /// Esc arrives here rather than as a keyDown, provided the panel is key.
    override func cancelOperation(_ sender: Any?) {
        onCancelOrResignKey?()
    }

    override func resignKey() {
        super.resignKey()
        onCancelOrResignKey?()
    }
}
```

- [ ] **Step 2: Build**

Run: `cd cli && swift build`
Expected: clean. If Swift objects that `NSPanel` methods cannot be `@MainActor`-isolated overrides, remove `@MainActor` from `KeyPanel` (AppKit views are main-actor by inheritance in Swift 6) and report what you changed.

- [ ] **Step 3: Confirm the suite is untouched**

Run: `make test`
Expected: **51 tests, 0 failures.**

- [ ] **Step 4: Commit**

```bash
git add cli/Sources/SpellCheckerBar/TranslationPanel.swift
git commit -m "feat: add the floating translation panel

An NSPanel hosting the SwiftUI content, centred in the upper third of the active
screen. Esc arrives via cancelOperation, which needs the panel to be key, so
showing it activates the app; clicking away is hidesOnDeactivate and losing key
inside the app is resignKey. An open panel is reused rather than stacked, and
update() ignores a closed panel so a late reply cannot resurrect it.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `TranslateCoordinator`, cancellation, and the shared clipboard read

**Files:**
- Create: `cli/Sources/SpellCheckerBar/TranslateCoordinator.swift`
- Create: `cli/Sources/SpellCheckerBar/Clipboard.swift`
- Modify: `cli/Sources/SpellCheckerBar/CheckCoordinator.swift`

**Interfaces:**
- Consumes: `TranslationHandle`, `TextTranslator`, `InputText`, `TranslationViewState`, `TranslationPanel`, `StatusItemController`.
- Produces: `func clipboardText() -> String?`; `@MainActor final class TranslateCoordinator` with `init(status: StatusItemController, translator: any TextTranslator)` and `func runTranslate()`.

- [ ] **Step 1: Extract the clipboard read**

Create `cli/Sources/SpellCheckerBar/Clipboard.swift`:

```swift
import AppKit

/// The clipboard's text, or nil when it holds none.
///
/// A non-text clipboard (an image) yields nil, which `InputText.check` already
/// classifies as `.noText` — so both coordinators treat "an image" and "nothing"
/// the same way, deliberately.
func clipboardText() -> String? {
    NSPasteboard.general.string(forType: .string)
}
```

In `CheckCoordinator.swift`, replace `NSPasteboard.general.string(forType: .string)` in `runCheck()` with `clipboardText()`. That is the only change to that file; leave the guard, the icon states and `evaluate` exactly as they are.

- [ ] **Step 2: Write the coordinator**

Create `cli/Sources/SpellCheckerBar/TranslateCoordinator.swift`:

```swift
import AppKit
import Foundation
import SpellCheckerCore
import SpellCheckerUI

/// Orchestrates one translation: guards against overlap, reads the clipboard,
/// runs the translator off the main actor, and drives the floating panel.
///
/// Has its **own** in-flight guard rather than sharing the checker's: they are
/// separate UIs, and a translation refusing because a check happened to be running
/// would just be puzzling. Two `claude` subprocesses at once is fine.
@MainActor
final class TranslateCoordinator {
    private let status: StatusItemController
    private let translator: any TextTranslator
    private let panel: TranslationPanel

    private var isTranslating = false
    private var handle: TranslationHandle?

    /// Bumped on every run. A reply from run *n* is dropped once run *n + 1* has
    /// started, so a slow translation cannot paint over a newer one — or over a
    /// panel the user has already dismissed and reopened.
    private var generation = 0

    init(status: StatusItemController, translator: any TextTranslator) {
        self.status = status
        self.translator = translator
        var dismissed: (() -> Void)?
        self.panel = TranslationPanel { dismissed?() }
        dismissed = { [weak self] in self?.handleDismissal() }
    }

    func runTranslate() {
        // Ignore re-triggers while a translation is in flight, matching the checker.
        // Pressing the hotkey while the panel is merely open starts a fresh one.
        guard !isTranslating else { return }

        let source: String
        switch InputText.check(clipboardText()) {
        case .ok(let trimmed):
            source = trimmed
        case let rejected:
            // Rejections are reported in the window, never in the icon: the panel is
            // this feature's UI, and a blinking icon with no window explains nothing.
            if let state = TranslationViewState.rejection(rejected) {
                panel.show(state)
            }
            return
        }

        generation += 1
        let run = generation
        isTranslating = true
        status.show(.translating)
        panel.show(.loading)

        let translator = self.translator
        Task {
            let state = await Self.translate(translator, source) { [weak self] handle in
                Task { @MainActor in self?.adopt(handle, for: run) }
            }
            guard self.generation == run else { return }   // a newer run owns the panel
            self.isTranslating = false
            self.handle = nil
            self.status.show(.neutral)
            self.panel.update(state)
        }
    }

    /// Keep the handle only while it belongs to the current run — a handle arriving
    /// after the user already dismissed the panel is cancelled immediately rather
    /// than stored, so no subprocess outlives the window that wanted it.
    private func adopt(_ handle: TranslationHandle, for run: Int) {
        guard generation == run, isTranslating else {
            handle.cancel()
            return
        }
        self.handle = handle
    }

    /// Esc or focus loss: kill the call, drop the icon back to neutral, and make
    /// sure a late reply has nothing to paint into.
    private func handleDismissal() {
        handle?.cancel()
        handle = nil
        if isTranslating {
            isTranslating = false
            generation += 1      // invalidate the in-flight run
            status.show(.neutral)
        }
    }

    /// Run the (blocking) translator off the main actor and map it to a view state.
    private static func translate(
        _ translator: any TextTranslator,
        _ source: String,
        onStart: @escaping @Sendable (TranslationHandle) -> Void
    ) async -> TranslationViewState {
        await Task.detached(priority: .userInitiated) {
            do {
                let result = try translator.translate(source, onStart: onStart)
                return TranslationViewState.from(result, source: source)
            } catch {
                FileHandle.standardError.write(Data("spell-checker-bar: \(error)\n".utf8))
                return TranslationViewState.failure(error)
            }
        }.value
    }
}
```

Note `status.show(.neutral)` rather than holding the result for four seconds: the panel is the UI now, so the icon's job ends when the call does.

- [ ] **Step 3: Build**

Run: `cd cli && swift build`
Expected: clean. Swift 6 strict concurrency is the likely friction here — the `onStart` closure crosses actors, which is why it is `@Sendable` and why it hops back with `Task { @MainActor in }`. If the compiler rejects the `dismissed` two-step in `init` (needed because the panel's callback wants `self`), replace it with a `lazy var panel` and say so in your report.

- [ ] **Step 4: Confirm the suite is untouched**

Run: `make test`
Expected: **51 tests, 0 failures.**

- [ ] **Step 5: Commit**

```bash
git add cli/Sources/SpellCheckerBar/TranslateCoordinator.swift cli/Sources/SpellCheckerBar/Clipboard.swift cli/Sources/SpellCheckerBar/CheckCoordinator.swift
git commit -m "feat: add TranslateCoordinator with real cancellation

Dismissing the panel cancels the in-flight call through the TranslationHandle,
because Task cancellation cannot reach a process blocked in a pipe read. A
generation counter stops a slow reply painting over a newer run or a reopened
panel, and a handle that arrives after dismissal is cancelled rather than stored.
Its in-flight guard is its own, not shared with the checker. The clipboard read is
now one helper both coordinators call.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The hotkey and the menu item

**Files:**
- Modify: `cli/Sources/SpellCheckerBar/Shortcuts.swift`
- Modify: `cli/Sources/SpellCheckerBar/AppDelegate.swift`

**Interfaces:**
- Consumes: `TranslateCoordinator`, `ClaudeCLITranslator`.
- Produces: `KeyboardShortcuts.Name.translateClipboard`, default **⌃⌥⌘⇧C**.

- [ ] **Step 1: Add the shortcut name**

In `Shortcuts.swift`, add below the existing `toggleCheck`:

```swift
    /// Global hotkey that translates the clipboard into the floating window.
    /// Default: Hyper+⇧C (⌃⌥⌘⇧C) — the checker's Hyper+C plus Shift.
    ///
    /// A fresh name, so no stored value exists for it and the code default applies.
    /// Note what slice 1 learned the hard way: `KeyboardShortcuts` writes this
    /// default into UserDefaults on first launch, and from then on the stored value
    /// wins — see Findings/keyboardshortcuts-persists-its-default. Changing it later
    /// needs a migration, not just an edit here.
    @MainActor static let translateClipboard = Self(
        "translateClipboard",
        default: .init(.c, modifiers: [.control, .option, .command, .shift])
    )
```

- [ ] **Step 2: Wire it in `AppDelegate`**

Add a stored property beside the existing coordinator:

```swift
    private var translateCoordinator: TranslateCoordinator!
```

In `applicationDidFinishLaunching`, after the existing `coordinator` line:

```swift
        translateCoordinator = TranslateCoordinator(
            status: status,
            translator: ClaudeCLITranslator()
        )
```

Add the menu item directly after `menu.addItem(checkItem)`:

```swift
        let translateItem = NSMenuItem(
            title: "Translate clipboard now",
            action: #selector(translateNow),
            keyEquivalent: ""
        )
        translateItem.target = self
        menu.addItem(translateItem)
```

Register the hotkey after the existing `onKeyDown` block:

```swift
        KeyboardShortcuts.onKeyDown(for: .translateClipboard) { [weak self] in
            MainActor.assumeIsolated {
                self?.translateCoordinator.runTranslate()
            }
        }
```

And add the action beside `checkNow`:

```swift
    @objc private func translateNow() {
        translateCoordinator.runTranslate()
    }
```

Leave `migrateLegacyToggleCheckShortcutIfNeeded()` exactly where it is — it is scoped to `toggleCheck` and has nothing to do with the new name.

- [ ] **Step 3: Build and confirm the suite**

Run: `cd cli && swift build && make test`
Expected: clean build; **51 tests, 0 failures.**

- [ ] **Step 4: Commit**

```bash
git add cli/Sources/SpellCheckerBar/Shortcuts.swift cli/Sources/SpellCheckerBar/AppDelegate.swift
git commit -m "feat: bind Hyper+⇧C to the translator

The checker's Hyper+C plus Shift, with a matching menu item so the feature is
discoverable without the hotkey and testable without focus games. A fresh
shortcut name, so no stored value exists and the code default applies.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Manual verification — the user at the keyboard

Everything in `SpellCheckerBar` is unreachable by tests, and window behaviour, focus and cancellation are only judgeable by a human. **Do not automate, simulate, or fake any of this, and do not synthesise keystrokes** — an earlier session had a subagent drive the UI with System Events and kill an unrelated process, which is not to be repeated.

**Files:** possibly `TranslationPanel.swift` (placement/metrics) and `TranslationView.swift` (spacing), if the by-eye pass calls for it.

- [ ] **Step 1: Build and launch the bundle**

```bash
pkill -f 'SpellChecker.app/Contents/MacOS/SpellChecker' || true
make run-app
```

Only one instance should run: another build of this app binds the same hotkeys and the same preferences domain, which is how slice 1's rebind looked broken when it was fine.

- [ ] **Step 2: The happy paths — three real `claude` calls, no more**

| clipboard | action | expected |
|---|---|---|
| `Could you take a look at my PR when you have a moment?` | Hyper+⇧C | 文A icon + "Translating…", then **one** Russian sentence, nothing else |
| `commit` | Hyper+⇧C | header `commit`, up to three numbered meanings with explanations and quoted examples, and "more meanings exist" |
| `sandwich` | Hyper+⇧C | word mode, and **no** "more meanings exist" — a narrow word has nothing left out |

- [ ] **Step 3: Dismissal**

Esc closes the panel. Reopen, then click into another app — it closes too. Confirm focus lands back somewhere sensible rather than leaving you in a dead app.

- [ ] **Step 4: Cancellation — the one that matters**

Copy a long paragraph, press Hyper+⇧C, and **while "Translating…" is still showing**, press Esc. Then immediately:

```bash
pgrep -f 'claude -p' || echo "no claude process — cancellation works"
```

Expected: no process. If one lingers, cancellation is not wired correctly — that is a real failure, not a timing artifact, and it is the whole reason `TranslationHandle` exists.

- [ ] **Step 5: The guards**

```bash
pbcopy </dev/null                        # → "Nothing to translate — the clipboard has no text."
printf 'a%.0s' $(seq 2001) | pbcopy      # → the too-long sentence, INSTANTLY, naming 2001 and 2000
```

The second must appear with no "Translating…" at all — that absence is the proof no LLM call was made.

- [ ] **Step 6: Layout, selection, and the other hotkey**

Paste a long text (several hundred characters) and translate it: the panel should scroll rather than run off screen. Select some Russian and press ⌘C — it should copy. Then press **Hyper+C**: the checker should still show its icon-only verdict, and the two features fired back to back should not interfere.

- [ ] **Step 7: Both menu items**

Click the status icon: "Check clipboard now" and "Translate clipboard now" should both work.

- [ ] **Step 8: Commit any tuning**

If Steps 2–6 called for changes to the metrics or spacing:

```bash
git add cli/Sources/SpellCheckerUI/TranslationView.swift cli/Sources/SpellCheckerBar/TranslationPanel.swift
git commit -m "fix: tune the translation panel's layout

Values found by looking at it on screen.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

If nothing needed changing, skip this commit and say so rather than inventing one.

---

### Task 9: Documentation and the vault

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `cli/README.md`
- Modify: `spell-checker-vault/Design/ad-hoc-translator.md`, `spell-checker-vault/Roadmap.md`, `spell-checker-vault/Ideas/inbox.md`

**Do not touch** anything under `spell-checker-vault/Sessions/`, the three earlier plan documents, or this plan.

- [ ] **Step 1: The app's own docs**

`CLAUDE.md`'s menu-bar paragraph currently describes one hotkey. Add the second, using this exact text after the existing ⌃⌥⌘C sentence:

```markdown
**⌃⌥⌘⇧C** (Hyper+⇧C) translates the clipboard **English → Russian** into a floating window —
one or two words return up to three meanings with simple-English explanations, longer text returns
just the translation. Esc or clicking away dismisses it and cancels the call. The window is the UI
for this feature, so input problems appear as sentences in it rather than as icon states.
```

In `README.md`, add one sentence to the overview:

```markdown
A second hotkey (**⌃⌥⌘⇧C**) translates the clipboard from English to Russian into a floating
window, for understanding what someone wrote to you.
```

In `cli/README.md`, in the section documenting the menu-bar app (the one that currently describes ⌃⌥⌘C and the icon legend), add this exact paragraph directly after the ⌃⌥⌘C description:

```markdown
Press **⌃⌥⌘⇧C** (Hyper+⇧C) to translate the clipboard from English into Russian in a floating
window. One or two words return up to three meanings with simple-English explanations and examples;
three or more words return just the translation. Esc — or clicking into another app — dismisses the
window and cancels the call. Because the window is this feature's whole UI, an empty or oversized
clipboard is reported as a sentence inside it rather than as a menu-bar icon.
```

- [ ] **Step 2: The vault**

- `spell-checker-vault/Design/ad-hoc-translator.md`: change the Slice 3 heading to match the "(shipped)" convention the other two now use, and update the header status line to say all three slices shipped. Then correct the note against what was actually built — in particular, **the cancellation section describes `ClaudeCLI.run` taking an `onStart: (Process) -> Void` and the coordinator calling `terminate()`.** What shipped is a public `TranslationHandle` whose `cancel()` hides the mechanism, because `TextTranslator` is the backend-swap point and an HTTP backend cancels a request rather than a subprocess. Rewrite that paragraph to describe the handle, and say why. Also record that `TranslationViewState` and the user-facing sentences live in `SpellCheckerUI` so they can be tested, since an executable target cannot be imported by the test bundle.
- `spell-checker-vault/Roadmap.md`: mark **Phase 2.3 complete** — all three slices — and note that the distribution track (Phase 2.1 GitHub, 2.2 Homebrew) is now the next thing, with Phase 3's polish loop after it.
- `spell-checker-vault/Ideas/inbox.md`: **add an item for deferring the window until the result is ready.** Requested 2026-08-05 after the manual pass. Today `runTranslate` opens the panel in `.loading` immediately; the request is that the 文A glyph in the menu bar be the only "working" signal, with the window appearing only when there is something to read. **Record the tension, because it is not obvious:** the panel is currently the *only* trigger for cancelling an in-flight call — Esc or focus loss calls `TranslationHandle.cancel()`. With no window during the wait there is nothing to dismiss, so cancellation loses its trigger entirely. Whoever implements this must either add a new one (pressing Hyper+⇧C again to cancel, or a "Cancel translation" menu item) or knowingly accept that the handle and generation counter sit inert until one exists. **Do not delete that machinery as dead code** — it solves a real problem (a subprocess outliving its window) and was verified to work.
- `spell-checker-vault/Ideas/inbox.md`: **add an item for showing each hotkey in the status-item menu.** Requested 2026-08-05 with a screenshot: "Check clipboard now" and "Translate clipboard now" show no key equivalent, while "Quit Spell Checker" displays ⌘Q and carries an icon. Set `keyEquivalent` and `keyEquivalentModifierMask` on both items so the menu documents the shortcuts (⌃⌥⌘C and ⌃⌥⌘⇧C), and give each an image the way Quit has one. Note that setting a key equivalent on a status-item menu item also makes it live while the menu is open, which is harmless here since the global hotkeys already do the same thing.
- `spell-checker-vault/Ideas/inbox.md`: **add a new item for the ⌘C failure found in the manual pass.** The window's text can be selected but ⌘C does not copy it. Record the likely cause so nobody repeats the investigation: `.textSelection(.enabled)` makes text selectable, but ⌘C needs a responder handling the `copy:` action, and in a normal app that routing comes from the main menu's **Edit → Copy** item. This app is `LSUIElement` with only a status-item menu and no application main menu at all, so the keystroke has nowhere to go. Two candidate fixes: install a minimal main menu containing an Edit menu with a Copy item, or handle `copy:` in the panel/hosting view directly. Note that the design's "no copy button, selection is enough" decision **depends on this working**, so if it turns out to be awkward the copy-button question is reopened rather than settled.
- `spell-checker-vault/Ideas/inbox.md`: the "Richer text input for the evaluator" item mentions a typed-in popup unlocking the polish loop. Append this exact sentence to that item, since the panel now exists and Phase 3 should not build a second one from scratch:

```markdown
  Phase 2.3's floating panel (`TranslationPanel` + `TranslationView`) is a working starting point
  for that popup — it already handles Esc/focus-loss dismissal, cancellation of an in-flight call,
  and placement, so the polish loop mainly needs an editable input instead of a read-only result.
```

- [ ] **Step 3: Verify**

```bash
make test        # 51 tests, 0 failures
make build
make app
grep -rn "⌃⌥⌘⇧C" CLAUDE.md README.md cli/README.md spell-checker-vault/ | head
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md cli/README.md spell-checker-vault
git commit -m "docs: document the floating translation window

Adds Hyper+⇧C to both READMEs and CLAUDE.md, marks Phase 2.3 complete, and
corrects the design note's cancellation section: what shipped is a public
TranslationHandle rather than the Process-shaped hook the note described, because
the backend-swap protocol must not assume a subprocess. Also records why the view
state lives in SpellCheckerUI — an executable target cannot be tested.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Slice 3 Definition of Done

- `make test` passes at **51 tests** (41 before + 3 handle + 1 concurrency + 6 view state).
- `make build` and `make app` both succeed.
- Hyper+⇧C opens the panel; Esc and clicking away both dismiss it.
- **Dismissing mid-flight leaves no `claude` process behind** (`pgrep -f 'claude -p'` is empty).
- Empty and oversized clipboards show sentences in the window; the oversized one appears instantly.
- A long translation scrolls; text selects and ⌘C copies.
- Hyper+C still runs the icon-only check, and the two do not interfere.
- Both menu items work.
- No live document describes the app as check-only, and the design note describes the handle rather than the `Process` hook.

## Not in this slice

Tracked in `spell-checker-vault/Ideas/inbox.md`: clickable "more…" expansion, Haiku for text mode, a copy button if real use asks for one, Ru → En autodetection, and translating the current selection instead of the clipboard. After this slice the roadmap's next item is the distribution track — Phase 2.1 (publish to GitHub) and Phase 2.2 (Homebrew, where the Nerd Font cask dependency matters) — then Phase 3's polish loop, which can reuse this panel.
