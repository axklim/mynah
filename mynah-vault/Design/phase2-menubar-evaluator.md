# Design — Phase 2: menu-bar evaluator

The first GUI slice. A menu-bar (system-tray) app where the global hotkey **⌃⌥⌘C** runs the
existing [[traffic-light-eval|traffic-light evaluator]] on the **clipboard** text and shows the
verdict **in the tray icon itself**. There is **no popup window** in this slice — the icon is the
entire UI.

This reshapes [[Roadmap|Phase 2]]: the roadmap originally said "hotkey opens an *empty* popup."
We instead pipe the real evaluator result into the icon — same effort, real end-to-end value on
the first GUI slice. The rewrite/polish loop (pillar 1) stays deferred.

## User-facing flow

1. **Launch** → an `NSStatusItem` appears in the menu bar showing the **neutral** icon (a hollow circle). The
   app is an **accessory** (`LSUIElement` / `.accessory`) — no Dock icon, no main window.
2. **Press ⌃⌥⌘C** → icon switches to the **working** state (an hourglass) while the check runs. If a check is
   already in flight, the press is **ignored** (see [[concurrent-recheck-while-busy]]).
3. **Read the text** → from the **clipboard** (`NSPasteboard.general`). Empty/no string is **not
   an error** — show a distinct **empty** icon (an outlined page) for the same ~4s, then revert. *Richer input
   later — current selection, or a typed-in popup — tracked in [[inbox]] ("Richer text input for
   the evaluator").*
4. **Evaluate** → run `ClaudeCLIEvaluator` on a background `Task` (shells out to `claude -p`,
   Sonnet). Reuses the existing evaluator unchanged.
5. **Show the verdict** → icon becomes a **green / yellow / red dot** (or a **warning triangle** on failure) for **~4 seconds**,
   then reverts to the neutral icon.

## Architecture — one SwiftPM package, three targets

The package stays in `cli/` (directory name kept to avoid churn; it now hosts both binaries —
revisit the name later if it grates). The evaluator is factored into a **shared library** so both
binaries share one implementation.

```
cli/Package.swift
  ├─ MynahCore   (library target)     Verdict, TextEvaluator, ClaudeCLIEvaluator — made `public`
  ├─ Mynah       (executable target)  binary: mynah      (the CLI; imports Core; main.swift)
  └─ MynahBar    (executable target)  binary: mynah-bar  (the menu-bar app; imports Core + KeyboardShortcuts)
```

- **`MynahCore`** — move `TextEvaluator.swift` and `ClaudeCLIEvaluator.swift` (and the
  `Verdict` enum) here; mark the shared types/functions `public`. Single source of truth.
- **`Mynah`** (CLI) — unchanged behaviour; `main.swift` now `import MynahCore`.
- **`MynahBar`** (app) — pure **AppKit** (`NSStatusItem`, `NSMenu`, `NSPasteboard`). **No
  SwiftUI in this slice** (it arrives with the popup/settings later). Depends on
  [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) for the global hotkey.

### Components inside `MynahBar`

- **`AppDelegate`** — `NSApplicationDelegate`; on launch sets `.accessory` activation policy,
  creates the status item, builds the click-menu (**Quit**, room for Settings later), and
  registers the hotkey handler.
- **`StatusItemController`** — owns the `NSStatusItem`; exposes `show(state:)` for the seven icon
  states (neutral / working / green / yellow / red / empty / error) and manages the ~4s revert
  timer.
- **`CheckCoordinator`** — orchestrates a single check: guards `isChecking`, reads the clipboard,
  calls `MynahCore`, maps the result to an icon state. A press during the display window
  cancels the pending revert and starts fresh; a press during the LLM call is ignored.

### Hotkey

- `KeyboardShortcuts.Name("toggleCheck")` with a baked-in **default of ⌃⌥⌘C**
  (`.c` + `[.control, .option, .command]`). Handler wired via `KeyboardShortcuts.onKeyDown`.
- `KeyboardShortcuts` is Carbon-backed → **no Accessibility/Input-Monitoring prompt**.
- A user-rebindable recorder UI is deferred → [[inbox]] ("Shortcut recorder UI"), Phase 3.

## Icon states

Emoji set as the status-item button **title** (simplest; matches the CLI's traffic-light
vocabulary). Upgrade to tinted SF Symbols later for polish.

| state    | codepoint | when |
|----------|-----------|------|
| neutral  | `U+F10C`  | idle / after the result window elapses |
| working  | `U+F252`  | check in flight |
| green    | `U+F111`  | verdict green |
| yellow   | `U+F111`  | verdict yellow |
| red      | `U+F111`  | verdict red |
| empty    | `U+F016`  | clipboard has no text — nothing to check (**not** an error) |
| tooLong  | `U+F02D`  | clipboard text over the 2000-character limit |
| error    | `U+F071`  | `claude` failure or unparseable output |

The emoji title above shipped as described, but was later replaced with tinted Nerd Font glyphs
(with an emoji fallback when the font is missing) — see [[0008-nerd-font-status-icons]] for the
decision and [[ad-hoc-translator]] Slice 1 for the implementation, which also added the `tooLong`
state reflected in the table above.

## Concurrency

`isChecking` is true **only during the LLM call**. Press handling:

- press while `isChecking` → **ignore** (no overlapping `claude` runs).
- press while *not* checking (incl. during the 4s display) → cancel any pending revert timer,
  start a new check.

Future: cancel-first-process-last, and a payload cache for instant repeats — see
[[concurrent-recheck-while-busy]] and [[inbox]] ("History + cache for instant repeats").

## Build & bundle (`make`, hand-assembled `.app`)

No Xcode project. New Makefile targets alongside the existing CLI ones:

- **`make app`** — `cd cli && swift build -c release`, then assemble `dist/Mynah.app`:
  - `Contents/MacOS/Mynah` ← the `mynah-bar` binary
  - `Contents/Info.plist` ← `CFBundleName`, `CFBundleIdentifier` (e.g. `io.klimov.mynah`),
    `CFBundleExecutable=Mynah`, `LSUIElement=true`, `LSMinimumSystemVersion=13.0`
  - optional ad-hoc sign: `codesign --force --sign - dist/Mynah.app`
- **`make run-app`** — `make app` then `open dist/Mynah.app`.
- Existing `make build` / `install` / `uninstall` / `clean` continue to serve the CLI.

`KeyboardShortcuts` is a pure-Swift package → statically linked into the binary; no extra
bundling step.

## Known risk — `PATH` when launched from Finder

A `.app` launched from Finder/`open` does **not** inherit the interactive shell `PATH`, so
`claude` (typically in `~/.local/bin`, Homebrew, or npm-global) is **not** on the default
`/usr/bin:/bin:/usr/sbin:/sbin` path and the shell-out fails. This only bites the GUI, not the
CLI (which inherits the terminal's `PATH`).

**Mitigation (shipped):** `ClaudeCLIEvaluator.resolveClaudeURL()` checks the known install
directories (`~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`) and
returns the first executable it finds. If none match it falls back to `/usr/bin/env claude`, which
works for terminal runs where `PATH` is inherited normally. A login-shell lookup
(`/bin/zsh -lc 'command -v claude'`) remains a possible future fallback for non-standard installs.
Recorded in Decision [[0006]].

**Second Finder-launch wrinkle — TCC prompts.** The `claude` subprocess inspects its working
directory on startup, so a Finder-launched `.app` (CWD = a user folder) triggers macOS privacy
prompts ("access your Downloads folder"). Fixed by pinning the subprocess CWD to a temp dir —
see [[gui-claude-subprocess-tcc-prompt]].

## Verification (all must pass before the slice is "done")

- `make app` produces `dist/Mynah.app`; launching it shows the **neutral** icon in the
  menu bar with **no Dock icon**.
- Clipboard = clear sentence → hourglass then **green**, reverts to neutral after ~4s.
- Clipboard = ambiguous/double-meaning sentence → **red**. Error-heavy-but-clear → **yellow**
  (reuse the [[traffic-light-eval]] verified examples).
- Clipboard empty → the **outlined-page** icon (distinct empty state, held ~4s, **not** treated as an error).
- Two fast ⌃⌥⌘C presses → the second is **ignored** while the first is in flight (one `claude`
  run, confirm via no double-spinner / single result).
- **Quit** from the menu terminates the app.
- `make build` + the CLI still work unchanged (regression check after the Core extraction).

## Out of scope (deferred)

Popup window, typed/selected-text input, rewrite/polish loop, settings screen, rebindable
shortcut, result history/cache, notifications, SwiftUI. Each is tracked in [[Roadmap]] / [[inbox]].

## Related

[[Home]] · [[Roadmap]] · [[Spec]] · [[traffic-light-eval]] · [[concurrent-recheck-while-busy]] ·
[[0003-build-toolchain-xcode-later]] · [[0006-polish-backend-claude-cli]] · [[inbox]]
