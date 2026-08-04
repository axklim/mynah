# CLAUDE.md — Project context

> **Read `spell-checker-vault/Home.md` first.** The Obsidian vault at [`spell-checker-vault/`](spell-checker-vault/Home.md) is the
> single source of truth for this project — ideas, decisions, problems, designs, and findings
> all live there. This file is just the quick orientation.

## What this is

A **native macOS app** that helps a non-native English speaker send clear, natural messages.

The developer writes messages all day (chat, email, PRs) and isn't always sure they read
clearly, sound natural, or are free of double meanings. Today the workflow is manual: write →
paste into ChatGPT with a fixed prompt → copy the result back. This app takes over that loop
**and** quietly learns from the mistakes so the developer improves over time.

## The two pillars

1. **Polish loop (daily, fast).** A global hotkey opens a lightweight popup. Type or paste a
   message, hit *Polish*, get **one** revised version from Claude, copy it back. There is always
   an explicit **"use my original / skip correction"** path for when the message is already good.

2. **Feedback & learning (periodic, reflective).** The app records the difference between what
   the developer wrote and the polished text and categorizes the mistakes — but it **does not
   explain in the moment**. Later, on demand, it surfaces:
   - a short overview of the most common mistakes,
   - simple grammar explanations & rules,
   - small exercises for the most frequent mistake topics,
   - a personal dictionary of frequent typing/spelling mistakes.

## Tech decisions (locked in — see `spell-checker-vault/Decisions/`)

| Area            | Decision                                                                 |
|-----------------|--------------------------------------------------------------------------|
| LLM             | Anthropic Claude — Haiku for polishing; Sonnet for evaluation/analysis (Haiku under-detected ambiguity — see Findings) |
| Invocation      | Menu bar app + global hotkey → popup; larger window for the dashboard    |
| Language / UI   | Swift 6 / SwiftUI + AppKit                                               |
| Build toolchain | `swift` CLT + `make`, no Xcode project — both the CLI and the menu-bar GUI app build this way (`make app`); AppKit/SwiftUI come with the CLT SDK (see Decision 0003) |
| Secrets         | Keychain (future GUI). The CLI evaluator needs no API key — it shells out to an authed `claude -p` (Decision 0006) |
| Storage         | Local, on-device (message text is sensitive — see Privacy in vault)      |

## Building & running

The code lives in `cli/` (a SwiftPM package) and builds two products (binary names can't contain
a hyphen, so each has a hyphen-free target/module — see `cli/Package.swift`):

- **`spell-checker`** (target `SpellChecker`) — the CLI evaluator.
- **`spell-checker-bar`** (target `SpellCheckerBar`) — the Phase 2 menu-bar app.

CLI targets:

- `make install` — build release + install `spell-checker` to `~/.local/bin` (override `PREFIX=…`)
- `make build` / `make uninstall` / `make clean`; bare `make` prints the target list
- Dev without installing: `cd cli && swift run spell-checker check "some text"`
- Run it: `spell-checker check "<text>"` (or `pbpaste | spell-checker check`) → one verdict 🔴/🟡/🟢

**Menu-bar app (Phase 2).** `spell-checker-bar` is an `LSUIElement` accessory app (no Dock icon):
the global hotkey **⌃⌥⌘C** (Hyper+C) (via the `KeyboardShortcuts` package) evaluates the clipboard text and
shows the verdict in the status-item icon for ~4s, then reverts: a green / yellow / red dot, an
outlined page when the clipboard has no text, a book when the text is over 2000 characters, or a
warning triangle on failure. The glyphs are JetBrainsMono Nerd Font codepoints tinted via
`IconTint`; without that font installed the app falls back to emoji.

- `make app` — build `cli/dist/SpellChecker.app` · `make run-app` — build and open it
- Dev without bundling: `cd cli && swift run spell-checker-bar`

Both products share **`SpellCheckerCore`** (`Sources/SpellCheckerCore/`), which holds the
`TextEvaluator` protocol, `Verdict`, `IconState`, and `ClaudeCLIEvaluator` — that's the single
backend-swap point. Today `ClaudeCLIEvaluator` shells out to `claude -p`, so a litellm/Gemini
backend can conform later without touching the CLI or the app.

Note: a Finder-launched `.app` doesn't inherit the shell `PATH`, so the evaluator resolves
`claude`'s absolute path (`resolveClaudeURL`) and runs it in an empty app-private working dir
(`Application Support/SpellChecker/claude-cwd`) so surrounding files never leak into a verdict —
see the vault Finding *gui-claude-subprocess-tcc-prompt*.

## Development philosophy

- **Incremental.** One small, self-contained slice per session.
- **Verify before moving on.** Every slice must be demonstrably working before the next starts.
- **Vault as the second brain.** Capture ideas, decisions, problems, and findings in `spell-checker-vault/`
  as we go. When something non-obvious is decided or discovered, write it down there.

See `spell-checker-vault/Roadmap.md` for the phased plan and current status.

## The polish prompt (verbatim — do not paraphrase)

```
Fix the grammar and make the text sound more natural. Use simple technical English and a
warm, cozy tone. Provide only one revised version:
```
