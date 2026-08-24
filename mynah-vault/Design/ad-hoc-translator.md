# Design — Ad-hoc translator (En → Ru)

> Status: **all three slices shipped** (2026-08-04, branch `ad-hoc-translator`). See [[Roadmap|Phase 2.3]].

A second hotkey that translates the clipboard and shows the result in a floating window — the
mirror of the [[traffic-light-eval|checker]]: that's about *what I'm about to send*, this is about
*what I just read*. Also rebinds the checker's hotkey and back-fills a guard it never had.

## Locked decisions

| Question | Decision |
|---|---|
| Direction | **En → Ru only**, no autodetection, at launch — **superseded** by [[configurable-language-pair]] (now a config setting, default flipped to En → De). Kept here as the original shipped decision. |
| Input | The **clipboard**, same as the checker — not the selection (needs Accessibility). |
| Length limit | **2000 characters**, shared with the checker. |
| Word vs text | **1–2 words** → word mode (up to 3 meanings + explanations). **3+** → text mode. |
| "more…" | Passive indicator only; clickable expansion is a follow-up ([[inbox]]). |
| Copy the result | No copy button/auto-copy — but **⌘C doesn't actually work** (nothing routes `copy:`), so this is reopened until [[inbox]]'s fix lands. |
| Icons | Nerd Font glyphs, not emoji — [[0008-nerd-font-status-icons]]. |

### Hotkeys

| shortcut | action |
|---|---|
| ⌃⌥⌘C (Hyper+C) | check the clipboard → verdict in the icon *(rebound from ⌃⌥C)* |
| ⌃⌥⌘⇧C (Hyper+⇧C) | translate the clipboard → floating window |

The rebind needed a one-time migration: `KeyboardShortcuts` persists its default into
`UserDefaults` on first launch, keyed by bundle identifier, so an old ⌃⌥C default is stuck there
forever once seen — editing the code default never reaches a machine that already ran an older
build. On launch the app resets the stored `.toggleCheck` shortcut to the current default **only**
if it's still exactly the legacy ⌃⌥C, guarded by a one-shot `UserDefaults` flag, so a deliberate
future rebind is never overridden. Full diagnosis: [[keyboardshortcuts-persists-its-default]].

---

## Slice 1 — Shared input guards, the rebind, Nerd Font icons

**Input guards.** `InputText.check` (`MynahCore/InputText.swift`) is the one guard rule for both
features — trim, reject empty, and enforce the 2000-character limit by `String.count`, not bytes
(Cyrillic is two bytes per character, so a byte limit would silently halve Russian text). Three
surfaces render the two failure cases differently:

| surface | `.noText` | `.tooLong` |
|---|---|---|
| CLI (`check`/`translate`) | stderr, exit 2 | stderr, exit 2, naming both numbers |
| menu-bar check | `empty` icon | `tooLong` icon |
| translator window | message in the window | message in the window |

**Icons.** Emoji → Nerd Font glyphs ([[0008-nerd-font-status-icons]]), font
`JetBrainsMonoNF-Regular` (the PostScript name, not the filename) in the **proportional** variant —
the Mono variant squeezes wide icons since the menu bar shows one glyph at a time.

| state | codepoint | glyph | tint | when |
|---|---|---|---|---|
| neutral | `U+F10C` | hollow circle | standard | idle |
| working | `U+F252` | hourglass | standard | check in flight |
| green/yellow/red | `U+F111` | filled circle | systemGreen/Yellow/Red | verdict |
| empty | `U+F016` | outlined empty page | standard | clipboard has no text |
| tooLong | `U+F02D` | closed book | standard | over the character limit |
| error | `U+F071` | warning triangle | systemOrange | claude failed / unparseable |
| translating | `U+F05CA` | 文A | standard | translation in flight |

![[icon-states.png]]

`tooLong` is deliberately distinct from `error` ("copied too much" vs. "claude broke" want
different reactions), and `translating` distinct from `working` (says which hotkey fired). Glyphs
are written as `\u{f111}` escapes, never pasted literal characters — those are private-use
codepoints that corrupt on re-type; an escape can't.

**Layering.** `MynahCore` imports no UI frameworks — `IconState` exposes a glyph string plus a
plain `IconTint` enum, and `StatusItemController` (Bar target) maps that to `NSColor`/`NSFont`. If
the font is missing (the Homebrew case), fall back to the current emoji as a plain title rather
than showing an empty box.

**Tests.** `InputText.check` boundary cases including the multibyte one; every `IconState` maps to
a glyph/tint; a font-coverage test (skipped, not failed, when the font's absent) using
`CTFontCopyCharacterSet` — not `CTFontGetGlyphsForCharacters`, which works in UTF-16 units and
false-negatives above U+FFFF ([[nerd-font-codepoint-identity]]).

---

## Slice 2 — Translator in Core + `mynah translate`

A second protocol beside `TextEvaluator`, same single-swap-point philosophy
([[0006-polish-backend-claude-cli]]): `TextTranslator.translate(_:) throws -> TranslationResult`,
with `.word(meanings:hasMore:)` for 1–2 words and `.text(String)` for longer input. The `claude`
shell-out (`resolveClaudeURL`, the empty app-private working dir that avoids TCC prompts —
[[gui-claude-subprocess-tcc-prompt]]) moved into a shared internal `ClaudeCLI.run`, so the evaluator
and translator can't drift on either hard-won lesson.

Word mode asks Claude for minified JSON (translation + simple-English explanation + example per
meaning), capped at 3, `hasMore` set only when real meanings were left out. Parsing is lenient like
`parseVerdict` — decode from the first `{` to the last `}` since `claude -p` sometimes fences JSON
anyway — and a failed/empty decode throws with the raw reply in the message rather than hiding it
behind a `--raw` flag. Model is Sonnet for both modes (Haiku under-performed on nuance here —
[[haiku-misses-ambiguity]]), exposed as `var model` so trying Haiku for text mode is a one-line
experiment ([[inbox]]).

`mynah translate <text>` (or stdin) mirrors `check`; text mode prints just the Russian so
`pbpaste | mynah translate | pbcopy` works, word mode prints a numbered list with a trailing
"more meanings exist" line when `hasMore`. Both `check` and `translate` share one `requireInput`
guard in `main.swift`, and the CLI's renderer (`TranslationResult.terminalText`) lives in
`MynahCore` rather than the CLI target — an executable target can't be imported by the test bundle,
and slice 1 already shipped a real bug of exactly that shape (an untested mapping was the only
thing telling a green verdict from a red one).

**Tests.** `TranslationMode.forInput` across word/text/edge-whitespace cases; `parseWordResult`
across clean/fenced/prefixed JSON, over-3-meanings clamping, and malformed input.

---

## Slice 3 — The floating translation window

An `NSPanel` subclass (`level = .floating`) hosting SwiftUI via `NSHostingView` — the project's
first use of SwiftUI, as always intended ([[0003-build-toolchain-xcode-later]]).

**Dismissal**, four mechanisms:
- **Esc while key** → `cancelOperation(_:)`.
- **The close button** → `KeyPanel.close()` override.
- **Focus loss** → *(changed 2026-08-24)* no longer closes outright — `resignKey()` starts a grace
  timer (`translationFocusGraceSeconds` config key, default 60s, `0` = the old instant-close
  behaviour), cancelled by `becomeKey()` if focus returns first. `hidesOnDeactivate` is off because
  app deactivation already resigns key status, so `resignKey()` covers switching apps too.
- **Esc while another app is key** → *(added 2026-08-24)* a global `NSEvent` monitor filtered to
  `kVK_Escape`, needed because a background panel is never first responder for that keystroke. A
  monitor only observes events sent to *other* apps, so it can't double-fire with
  `cancelOperation(_:)` or swallow the keystroke. Needs the Accessibility permission — nothing else
  here does, since the global hotkeys use `KeyboardShortcuts`' Carbon mechanism instead — requested
  once per install on launch (`requestAccessibilityPermissionIfNeeded`, guarded like the shortcut
  migration above) rather than nagging every launch if not granted.

An in-flight translation is **not** cancelled by mere focus loss, only by an actual close.

**Content.** `TranslationViewState` (loading/text/word/failed) and its user-facing sentences live
in `MynahUI`, not the `MynahBar` executable, for the same untestable-executable-target reason as
slice 2's renderer. Guard rejections and Claude failures render as full sentences in the window
(never as an icon state or an error code). Fixed 420pt width, height fits content up to 520pt then
scrolls (2000 Cyrillic characters would otherwise run off-screen); the panel sizes itself from the
hosting view's `fittingSize` rather than a hard-coded height, since `ScrollView` doesn't shrink to
short content the way `VStack` does.

**TranslateCoordinator** mirrors `CheckCoordinator` with its own `isTranslating` guard — separate
UIs, so a translation shouldn't refuse just because a check is running. Re-pressing the hotkey
while the panel is merely open starts a fresh translation and replaces the contents.

**Cancellation is the one real complexity.** Dismissing mid-flight must kill the `claude`
subprocess — `Task` cancellation can't, since the task blocks in `readDataToEndOfFile()` on a
`Process` that knows nothing about cooperative cancellation. So `TextTranslator.translate` hands
back a `TranslationHandle` whose `cancel()` hides *how* the work stops (today: `process.terminate()`),
rather than exposing the `Process` itself — a future non-subprocess backend needs to cancel a
request, not kill a process. `TranslationHandle` is a plain class, not an actor, so `cancel()` can
run synchronously from the main actor while translation runs on a background task. A generation
counter stops a late reply from run *n* painting into run *n+1*'s panel.

**Menu.** "Translate clipboard now" joins "Check clipboard now".

---

## Out of scope / follow-ups

Tracked in [[inbox]]: clickable "more…" expansion, Haiku for text mode, a copy button if real use
asks for one, Ru → En autodetection, translating the selection instead of the clipboard.

## Related

[[Home]] · [[Spec]] · [[Roadmap]] · [[traffic-light-eval]] · [[phase2-menubar-evaluator]] ·
[[0006-polish-backend-claude-cli]] · [[0008-nerd-font-status-icons]] ·
[[nerd-font-codepoint-identity]] · [[gui-claude-subprocess-tcc-prompt]] ·
[[haiku-misses-ambiguity]] · [[concurrent-recheck-while-busy]] ·
[[keyboardshortcuts-persists-its-default]]
