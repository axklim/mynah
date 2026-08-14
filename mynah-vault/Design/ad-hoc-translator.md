# Design — Ad-hoc translator (En → Ru)

> Status: **all three slices shipped**. Brainstormed 2026-08-04 on branch `ad-hoc-translator`.
> Ships in three slices; each is separately verifiable. See [[Roadmap|Phase 2.3]].

A second hotkey that translates the clipboard from **English to Russian** and shows the result in
a floating window. Unlike the [[traffic-light-eval|checker]] — which is about *what I am about to
send* — this is about *what I just read*: someone writes English, and the developer wants to be
sure they understood it.

It also rebinds the existing checker, and back-fills a guard the checker never had.

## Locked decisions

| Question | Decision |
|---|---|
| Direction | **En → Ru only.** No autodetection. Pasting Russian is undefined behaviour, accepted knowingly. — **Superseded** by [[configurable-language-pair]]: the direction is now a config setting, both sides configurable, default flipped to **En → De**. Kept here verbatim as the original decision this project shipped with. |
| Input | The **clipboard**, same as the checker. Not the selection (that needs Accessibility permission). |
| Length limit | **2000 characters**, shared by both features. |
| Word vs text | **1–2 words** → word mode. **3+** → text mode. |
| "more…" | **Passive indicator only.** Clickable expansion is a follow-up ([[inbox]]). |
| Copy the result | **No copy button, no auto-copy.** Selection is enabled, but **⌘C does not currently copy** — nothing routes the `copy:` action. This decision is provisional, not settled, and stays reopened until the follow-up in [[inbox]] lands. |
| Icons | **Nerd Font glyphs**, not emoji — see [[0008-nerd-font-status-icons]]. |

### Hotkeys

| shortcut | action |
|---|---|
| **⌃⌥⌘C** (Hyper+C) | check the clipboard → verdict in the icon *(rebound from ⌃⌥C)* |
| **⌃⌥⌘⇧C** (Hyper+⇧C) | translate the clipboard → floating window |

The first half of "the rebind is safe" holds: `KeyboardShortcuts.Name(_:default:)` only consults
the code default when no shortcut is already stored in `UserDefaults`. The second half was
**wrong** — the library's own `Name.swift` init writes that default into `UserDefaults` the very
first time the name is seen, so after any version's first launch the stored value wins
**permanently**. Editing the code default in `Shortcuts.swift` cannot rebind a machine that already
ran an older build — which is why the migration below exists. `UserDefaults` is keyed by **bundle
identifier**, so every build sharing `io.klimov.mynah` reads and writes the same stored
value; an older build only re-seeds the legacy ⌃⌥C when the stored key is **absent** — with Hyper+C
already stored, an older build reads that value back like any other. See
[[keyboardshortcuts-persists-its-default]] for the narrower recovery hazard this leaves (a one-shot
migration flag that can't self-heal a re-seeded key) and how this was diagnosed.

**Migration (Task 8b, shipped).** On launch, the app checks the stored `.toggleCheck` shortcut: if
it is exactly the legacy ⌃⌥C, it is reset to the current default (⌃⌥⌘C) — once, guarded by a
`migratedToggleCheckToHyperC` flag in `UserDefaults`. Guarding on an exact match (rather than
resetting unconditionally) means a deliberate rebind via the future Phase 3 recorder UI is never
overridden by this migration.

## Why three slices

The prompt work is where the uncertainty lives — whether Claude reliably returns three clean
translations with simple-English explanations, and whether `New York` behaves sensibly in word
mode. Iterating on that in a terminal costs seconds per attempt; iterating through a GUI means
rebuild the `.app`, copy text, press the hotkey, squint at a window — and a JSON decode failure
would be debugged blind. This is also how the evaluator was built (CLI in Phase 1, GUI in Phase 2),
and it leaves a permanent `mynah translate` behind.

---

## Slice 1 (shipped) — Shared input guards, the rebind, and Nerd Font icons

### One guard rule in Core, three renderings

The checker's guards are currently inline and incomplete: `CheckCoordinator.runCheck()` rejects
empty clipboards, the CLI rejects empty input, and **neither has a length limit** — a stray ⌘A⌘C
of a whole page goes straight to Claude, slowly and pointlessly. New in
`Sources/MynahCore/InputText.swift`:

```swift
public enum InputCheck: Sendable, Equatable {
    case ok(String)          // trimmed, non-empty, within the limit
    case noText              // nil, empty, or whitespace only
    case tooLong(count: Int) // probably a misclick
}

public enum InputText {
    public static let characterLimit = 2000
    public static func check(_ raw: String?) -> InputCheck
}
```

Trim whitespace and newlines, then count `String.count` — **characters, not bytes**. Em-dashes and
arrows already make the two diverge, and Cyrillic is two bytes per character, so a byte limit would
silently halve any Russian text if the direction ever flips.

Three call sites consume it:

| surface | `.noText` | `.tooLong` | lands in |
|---|---|---|---|
| CLI `check` | stderr, exit 2 | stderr, exit 2, naming both numbers | slice 1 |
| menu-bar check | `empty` icon | `tooLong` icon | slice 1 |
| CLI `translate` | stderr, exit 2 | stderr, exit 2, naming both numbers | slice 2 |
| translator window | message in the window | message in the window | slice 3 |

The too-long CLI message names the count and the limit, because when it fires you want to know
whether you misclicked or the limit is simply too tight.

### Icon states

Emoji out, Nerd Font in ([[0008-nerd-font-status-icons]]). Font:
**`JetBrainsMonoNF-Regular`** — the PostScript name; `JetBrainsMonoNerdFont-Regular` is only the
filename. The **proportional** variant, not `JetBrainsMonoNFM-Regular`: the Mono variant forces
every glyph into one fixed cell, squeezing the wide icons, and the menu bar shows one glyph at a
time so there is nothing to align to.

| state | codepoint | glyph | tint | when |
|---|---|---|---|---|
| neutral | `U+F10C` | hollow circle | standard — `labelColor`, follows appearance | idle |
| working | `U+F252` | hourglass | standard | check in flight |
| green | `U+F111` | filled circle | systemGreen | verdict green |
| yellow | `U+F111` | filled circle | systemYellow | verdict yellow |
| red | `U+F111` | filled circle | systemRed | verdict red |
| empty | `U+F016` | outlined empty page | standard | clipboard has no text |
| tooLong | `U+F02D` | closed book | standard | over the character limit |
| error | `U+F071` | warning triangle | systemOrange | claude failed / unparseable |
| translating | `U+F05CA` | 文A translate | standard | translation in flight *(slice 3, not yet implemented)* |

![[icon-states.png]]

`IconTint.secondary` has since been removed (commit `f9fdd1a`): `empty` and `tooLong` shipped
dimmed at `secondaryLabelColor` and looked too faint to read in a real menu bar, so both moved to
full-contrast `standard`. What distinguishes them from a verdict now is glyph shape, not a dimmer
colour.

`tooLong` is deliberately **not** `error`: "you copied a whole page" and "claude broke" want
different reactions. `translating` is deliberately **not** `working`: the icon should say which of
the two hotkeys was pressed.

Glyphs are written in Swift as **`\u{f111}` escapes, never as pasted literal characters** — these
are private-use codepoints that corrupt when retyped out of a rendered terminal. An escape cannot
corrupt, and it greps.

### Layering

`MynahCore`'s rule is narrower than "imports nothing" — it is **no UI frameworks in Core**.
`IconState` exposes `glyph: String` (the escape) plus `tint: IconTint` — a plain enum of
`.standard / .green / .yellow / .red / .orange`. `StatusItemController` maps `IconTint` to
`NSColor`, builds an `NSAttributedString` with the font, colour and a small `.baselineOffset`
nudge, and assigns `button.attributedTitle`. Core never learns what AppKit is, and swapping fonts
(or moving to SF Symbols) is one file in the Bar target.

**Learned in execution — imports are file-scoped.** Files in `MynahCore` declare their own
`import Foundation` when they use Foundation APIs, rather than relying on a sibling file's import
in the same target. Swift's `import` is per-file, not per-module/target: relying on a sibling
file's import compiles today — debug and release alike — but is undefined by contract, not a
guarantee the toolchain owes you. This doesn't relax the rule above; it just means each file states
its own dependencies honestly.

**Fallback:** if `NSFont(name: "JetBrainsMonoNF-Regular", size:)` returns nil, fall back to the
current emoji as a plain title. Without it, a machine missing the font shows an empty box where the
app's only UI lives — and that machine is exactly the Homebrew case ([[Roadmap|Phase 2.2]]).
`Verdict.display` keeps its emoji: in a terminal, 🟢 is the right answer.

The `.baselineOffset` value has to be found by looking at the real menu bar. A rendered PNG proves
the colours and shapes, not the vertical centring.

### Tests

- `InputText.check`: nil, empty, whitespace-only, exactly 2000, 2001, and a multibyte case
  (Cyrillic plus an em-dash) that passes a byte check but fails a character check.
- `IconState`: every state maps to a non-empty glyph and the expected tint.
- Font coverage: with AppKit, assert `JetBrainsMonoNF-Regular` covers every codepoint `IconState`
  declares — **skipped**, not failed, when the font is absent, so the suite still passes elsewhere.
  Use `CTFontCopyCharacterSet`, *not* `CTFontGetGlyphsForCharacters`: the latter works in UTF-16
  units and reports false negatives for every codepoint above U+FFFF
  ([[nerd-font-codepoint-identity]]).

### Docs to update in the same commit

`CLAUDE.md` names ⌃⌥C twice; `Spec.md` and [[phase2-menubar-evaluator]] each name it once, and both
describe the emoji icon set. So do `README.md`, `cli/README.md`, the `Makefile`, [[Roadmap]],
[[concurrent-recheck-while-busy]], and [[inbox]] — nine locations in total, all confirmed by grep.

---

## Slice 2 (shipped) — Translator in Core + `mynah translate`

### Types

A second protocol beside `TextEvaluator`, same single-swap-point philosophy
([[0006-polish-backend-claude-cli]]):

```swift
public protocol TextTranslator: Sendable {
    func translate(_ text: String) throws -> TranslationResult
}

public enum TranslationMode: Sendable, Equatable {
    case word   // 1–2 words
    case text   // 3+
    public static func forInput(_ text: String) -> TranslationMode
}

public struct WordMeaning: Sendable, Equatable, Codable {
    public let translation: String   // Russian
    public let explanation: String   // simple English
    public let example: String       // simple English
}

public enum TranslationResult: Sendable, Equatable {
    case word(meanings: [WordMeaning], hasMore: Bool)   // 1...3 meanings
    case text(String)                                   // just the Russian
}
```

### Extracting the claude shell-out

`runClaude(prompt:)`, `resolveClaudeURL()` and `claudeWorkingDirectory()` are private to
`ClaudeCLIEvaluator`, and the translator needs all three. They move to an internal
`ClaudeCLI.run(prompt:model:onStart:)` in Core. This keeps two hard-won lessons in exactly one
place — the Finder `PATH` resolution and the empty app-private working directory that stopped the
TCC prompts ([[gui-claude-subprocess-tcc-prompt]]). Duplicating them is how one copy drifts and
only the GUI breaks, months later, in a way that costs an evening to re-diagnose.

`ClaudeCLIEvaluator` shrinks to prompt + `parseVerdict`. `ClaudeCLITranslator` is prompt +
`parseWordResult`. `onStart` exists for slice 3's cancellation.

### Prompts

**Text mode** asks for the translation and nothing else; the reply is used verbatim, so there is
nothing to parse and nothing to break.

**Word mode** asks for minified JSON:

```json
{"meanings":[{"translation":"…","explanation":"…","example":"…"}],"hasMore":true}
```

Capped at 3 meanings, most common first; explanations in simple English of roughly 15 words; one
short natural example sentence per meaning; `hasMore` true only when further common meanings were
left out. That flag is the whole source of the passive "more…" line.

**Parsing stays lenient**, in the same spirit as `parseVerdict`. `claude -p` will sometimes wrap
JSON in ```` ```json ```` fences however firmly you ask it not to, so decode the slice from the
first `{` to the last `}`. More than 3 meanings → keep 3 and force `hasMore = true`. Zero meanings
or a failed decode → throw, with the raw reply in the message. No `--raw` flag: that error message
*is* the debugging path, and it costs nothing.

**Model:** Sonnet for both, matching the evaluator — Haiku already under-performed on nuance here
([[haiku-misses-ambiguity]]). Exposed as `var model`, so trying Haiku for text mode is a one-line
experiment once the prompts settle ([[inbox]]).

### CLI

```
mynah translate <text>     Translate English → Russian
mynah translate            Read the text from stdin
```

Text mode prints the Russian alone, so `pbpaste | mynah translate | pbcopy` works. Word
mode prints:

```
commit
  1. совершать (что-то), делать — to do or carry out an action, especially a crime or mistake
     "He committed a serious error in the report."
  2. обязываться, брать на себя обязательство — to promise or dedicate yourself to a course of action or relationship
     "She committed to finishing the project by Friday."
  3. коммит (в системе контроля версий) — to save a set of code changes permanently to a version control repository
     "Don't forget to commit your changes before pushing."
  … more meanings exist
```

The last line appears only when `hasMore`.

**Learned in execution.** The input guard is not duplicated per subcommand: both `check` and
`translate` call one `requireInput` helper in `main.swift`, which reads stdin or the joined
arguments and applies `InputText.check` once, so the two commands cannot silently diverge on
rejection wording or the length limit. The renderer above is
`TranslationResult.terminalText(source:)`, living in `MynahCore` rather than in the CLI
target — an executable target cannot be imported by the test bundle, and slice 1 shipped a real
defect of exactly that shape (an untested mapping was the only thing distinguishing a green verdict
from a red one), so this time the renderer stayed in Core, under test.

### Tests

Pure, no network: `forInput` on `commit` / `New York` / `look up` → word, `commit the change` →
text, plus odd whitespace and a hyphenated single word; and `parseWordResult` across clean JSON,
fenced JSON, JSON behind leading prose, four meanings clamped to three with `hasMore` forced, zero
meanings, and malformed input.

### Manual verification

- `translate "commit"` → up to 3 meanings, Russian, simple-English explanations and examples.
- `translate "Could you take a look at my PR when you have a moment?"` → one Russian sentence,
  nothing else.
- `translate "New York"` → word mode, sensible output.
- Empty input and a 3000-character input each exit 2, the latter naming both numbers.
- **Regression:** `mynah check` still prints one verdict after the `ClaudeCLI` extraction.

---

## Slice 3 (shipped) — The floating translation window

### The panel

An `NSPanel` subclass — `level = .floating`, `isFloatingPanel = true` — hosting SwiftUI via
`NSHostingView`. This is where SwiftUI finally enters the project, as the stack decision always
intended ([[0003-build-toolchain-xcode-later]]). No new package dependency; SwiftUI ships with the
CLT SDK.

Dismissal is two mechanisms, because it is two different events:

- **Esc** → the subclass overrides `cancelOperation(_:)` and closes. For that key to arrive the
  panel must be key, so opening calls `NSApp.activate(ignoringOtherApps: true)`.
- **Focus loss** → `hidesOnDeactivate = true` covers clicking into another app; a `didResignKey`
  observer covers losing key within the app. On close, `NSApp.hide(nil)` hands focus back to
  whatever you were reading. That last part is a by-feel detail, two lines either way.

### Content

```swift
enum TranslationViewState {
    case loading                                     // 文A + "Translating…"
    case text(String)                                // the Russian, alone
    case word(source: String, meanings: [WordMeaning], hasMore: Bool)
    case failed(String)                              // guard rejection or claude error
}
```

**Learned in execution.** `TranslationViewState` and every user-facing sentence it produces live in
`MynahUI` rather than in the `MynahBar` executable target, because an executable
target cannot be imported by the test bundle — slice 1 shipped a real defect of exactly that shape
(an untested mapping was the only thing distinguishing a green verdict from a red one).

Word mode: the source word as a header, then numbered rows — Russian prominent, simple-English
explanation beneath in secondary text, the example quoted below that — and a dim "more meanings
exist" footer only when `hasMore`. Text mode shows just the Russian; the English was copied a
second ago, reprinting it is noise.

Body text uses the **system font** — the Nerd Font is for icon glyphs only. Everything is
`.textSelection(.enabled)`, so text selects — but that does **not** settle the copy question: ⌘C
does not copy, because nothing routes the `copy:` action (diagnosis in [[inbox]]). The "no copy
button, selection is enough" decision is reopened until that's fixed.

Fixed width **420pt**; height fits the content up to **520pt**, beyond which a `ScrollView` takes
over — not optional, since 2000 characters of Russian would otherwise run off the bottom of the
screen. Placed horizontally centred on `NSScreen.main` in the upper third: Spotlight-like and
predictable, rather than chasing a mouse that was not involved in pressing a keyboard shortcut.
(Both numbers are starting points to be judged on screen, like the `.baselineOffset` nudge.)

**Learned in execution.** The panel doesn't hard-code a height — it sizes itself from the hosting
`NSHostingView`'s `fittingSize`, clamped between a small minimum and `maxHeight`, because a
`ScrollView` does not shrink to fit short content the way a `VStack` does; without the clamp, every
state would open at the full 520pt, mostly empty for a one-line reply.

### TranslateCoordinator

Mirrors `CheckCoordinator`, with its **own** `isTranslating` guard rather than one shared with the
checker — they are separate UIs, and a translation refusing because a check is running would just
be puzzling. Two `claude` subprocesses is fine.

Flow: guard → `InputText.check(clipboardText())` → a rejection opens the panel with that message
(the translator reports errors in the window, never in the icon) → `.ok` opens the panel in
`.loading`, sets the icon to `translating`, runs the translator off the main actor, then renders.
The icon returns to neutral when the call finishes; it does not hold a result for 4s, because the
panel is the UI now.

A small `clipboardText()` helper in the Bar target is shared by both coordinators.

Pressing Hyper+⇧C **while a translation is in flight** is ignored, matching the checker's rule.
Pressing it while the panel is merely *open* starts a fresh translation of whatever is on the
clipboard now and replaces the contents — the panel is reused, not stacked.

### Cancellation — the one piece of real complexity

Dismissing the panel mid-flight must kill the `claude` process. Swift `Task` cancellation will not
do it: the task is blocked in `readDataToEndOfFile()` on a `Process` that knows nothing about
cooperative cancellation, so the subprocess runs to completion, a translation nobody reads gets
paid for, and a late reply arrives at a closed panel.

So `TextTranslator.translate(_:onStart:)` never hands the coordinator a `Process` — it hands back a
public `TranslationHandle` whose `cancel()` hides *how* the work actually stops. Today that means
`ClaudeCLI.run`'s internal `onStart: (Process) -> Void` hook feeds `ClaudeCLITranslator` a live
`Process`, which it wraps as `TranslationHandle { process.terminate() }` before the handle ever
leaves Core; the coordinator only ever calls `.cancel()`. This indirection exists because
`TextTranslator` is the documented backend-swap point ([[0006-polish-backend-claude-cli]]): a
protocol method that handed back a `Foundation.Process` could never be implemented by a future
litellm/HTTP backend, which cancels a request rather than killing a subprocess. `TranslationHandle`
is a locked, idempotent class rather than an `actor` on purpose, so `cancel()` can be called
synchronously from the main actor (Esc, focus loss) while the translation itself runs on a
background task — an `actor` would force `async` everywhere and reintroduce the reliability problem
this exists to fix. A generation counter still prevents a late reply from run *n* rendering into
the panel from run *n+1*, and stops a handle from being adopted for a run that has already been
dismissed. About fifteen lines; skipping them is what turns into "why is my fan spinning".

### Errors read as sentences

- "Nothing to translate — the clipboard has no text."
- "That's 4820 characters, over the 2000 limit — did you mean to copy that much?"
- "Couldn't reach claude." plus a short detail.

### Menu

"Translate clipboard now" joins "Check clipboard now" — discoverable without the hotkey, and
testable without focus games.

### Verification

- Sentence copied → loading, then one Russian sentence. Esc closes it.
- Single word copied → up to 3 meanings with explanations and examples; "more meanings exist"
  appears for `run` or `commit`, not for a narrow word.
- Clicking another app mid-translation closes the panel **and** kills the process — confirm with
  `pgrep -f claude`.
- Empty clipboard → the no-text message. 3000 characters → the too-long message, **instantly**,
  proving no LLM call happened.
- A long translation scrolls and stays on screen.
- Text selects; **⌘C does not copy** — a real gap found in this pass, tracked in [[inbox]].
- Hyper+C still runs the icon-only check; the two fired back to back do not interfere.
- Both menu items work.

---

## Out of scope / follow-ups

Tracked in [[inbox]]: clickable "more…" expansion, Haiku for text mode, a copy button if real use
asks for one, Ru → En autodetection, and translating the current selection instead of the
clipboard. The rebindable-shortcut recorder UI and the payload cache were already there.

## Related

[[Home]] · [[Spec]] · [[Roadmap]] · [[traffic-light-eval]] · [[phase2-menubar-evaluator]] ·
[[0006-polish-backend-claude-cli]] · [[0008-nerd-font-status-icons]] ·
[[nerd-font-codepoint-identity]] · [[gui-claude-subprocess-tcc-prompt]] ·
[[haiku-misses-ambiguity]] · [[concurrent-recheck-while-busy]] ·
[[keyboardshortcuts-persists-its-default]]
