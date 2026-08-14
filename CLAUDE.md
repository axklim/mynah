# CLAUDE.md — Project context

> **Read `mynah-vault/Home.md` first.** The Obsidian vault at [`mynah-vault/`](mynah-vault/Home.md) is the
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

## Tech decisions (locked in — see `mynah-vault/Decisions/`)

| Area            | Decision                                                                 |
|-----------------|--------------------------------------------------------------------------|
| LLM             | Anthropic Claude — Haiku for polishing; Sonnet for evaluation/analysis (Haiku under-detected ambiguity — see Findings) |
| Invocation      | Menu bar app + global hotkey → popup; larger window for the dashboard    |
| Language / UI   | Swift 6 / SwiftUI + AppKit                                               |
| Build toolchain | `swift` CLT + `make`, no Xcode project (`make app` bundles the GUI). AppKit/SwiftUI come with the CLT SDK, but **`mynah-bar` still needs full Xcode** — a dependency uses `#Preview`, whose macro plugin is Xcode-only (Decision 0003's correction · Finding `preview-macro-needs-xcode`). The `mynah` CLI is CLT-only. |
| Distribution    | Homebrew via `axklim/homebrew-tap`, which installs **prebuilt** CLI + app from one release asset — nothing is compiled by brew (Decision 0011; Decision 0010 is the superseded repo-as-tap, CLI-only version) |
| Secrets         | Keychain (future GUI). The CLI evaluator needs no API key — it shells out to an authed `claude -p` (Decision 0006) |
| Storage         | Local, on-device (message text is sensitive — see Privacy in vault)      |
| Config          | XDG file at `$XDG_CONFIG_HOME/mynah/config.conf` (fallback `~/.config/mynah/config.conf`); `key = value`, hand-parsed, no dependency (Decision 0012) |

## Building & running

The code lives in `cli/` (a SwiftPM package) and builds two products (binary names are lowercase
and may contain hyphens; module names are CamelCase and can't — see `cli/Package.swift`):

- **`mynah`** (target `Mynah`) — the CLI evaluator.
- **`mynah-bar`** (target `MynahBar`) — the Phase 2 menu-bar app.

CLI targets:

- `brew install axklim/tap/mynah` — the installed path, and it ships **both** products prebuilt
  (`bin/mynah` + `Mynah.app`, started with `brew services start mynah`). The formula lives in
  `axklim/homebrew-tap`, not here; the release workflow bumps it cross-repo (Decision 0011)
- `make install` — build release + install `mynah` to `~/.local/bin` (override `PREFIX=…`).
  Pass `SWIFT_FLAGS=…` to add `swift build` flags. (Nothing needs it today; the formula stopped
  building from source in Decision 0011.)
- `make build` / `make uninstall` / `make clean`; bare `make` prints the target list
- `make version` — print the version. It has **one** home,
  `cli/Sources/MynahCore/MynahVersion.swift`: `mynah --version` reads it, and `make app`
  generates `Info.plist` from `Info.plist.in` with it substituted in, so a bump is that one
  line (release steps in Decision 0011)
- Dev without installing: `cd cli && swift run mynah check "some text"`
- Run it: `mynah check "<text>"` (or `pbpaste | mynah check`) → one verdict 🔴/🟡/🟢
- Translate it: `mynah translate "<text>"` (or `pbpaste | mynah translate`) — between the
  **configured language pair**, defaulting to **English → German**. Change it by editing the config
  file (`mynah config` shows where it lives); no autodetection either way. One or two words return
  up to three meanings, each with a simple-English explanation and an example; three or more words
  return just the translation.
- `mynah config` — print the effective config and where it lives.
  `mkdir -p ~/.config/mynah && mynah config > ~/.config/mynah/config.conf` writes a starter file.
  Only use it to create the file the first time: the shell truncates the target before `mynah`
  runs, so re-running the same command against an existing config reads it back empty and
  silently overwrites it with defaults.

**Menu-bar app (Phase 2).** `mynah-bar` is an `LSUIElement` accessory app (no Dock icon):
the global hotkey **⌃⌥⌘C** (Hyper+C) (via the `KeyboardShortcuts` package) evaluates the clipboard text and
shows the verdict in the status-item icon for ~4s, then reverts: a green / yellow / red dot, an
outlined page when the clipboard has no text, a book when the text is over 2000 characters, or a
warning triangle on failure.

**⌃⌥⌘⇧C** (Hyper+⇧C) translates the clipboard between the **configured language pair** (default
**English → German**) into a floating window, re-reading the config file on every press so an edit
takes effect without restarting — one or two words return up to three meanings with explanations in
the source language, longer text returns just the translation. Esc or clicking away dismisses it and
cancels the call. The window is the UI for this feature, so input problems (including a broken
config file) appear as sentences in it rather than as icon states.

The glyphs are JetBrainsMono Nerd Font codepoints tinted via
`IconTint`; without that font installed the app falls back to emoji.

- `make app` — build `cli/dist/Mynah.app` · `make run-app` — build and open it
- Dev without bundling: `cd cli && swift run mynah-bar`

Both products share **`MynahCore`** (`Sources/MynahCore/`), which holds the
`TextEvaluator` protocol, `Verdict`, `IconState`, and `ClaudeCLIEvaluator` — that's the single
backend-swap point. Today `ClaudeCLIEvaluator` shells out to `claude -p`, so a litellm/Gemini
backend can conform later without touching the CLI or the app.

Note: a Finder-launched `.app` doesn't inherit the shell `PATH`, so the evaluator resolves
`claude`'s absolute path (`resolveClaudeURL`) and runs it in an empty app-private working dir
(`Application Support/Mynah/claude-cwd`) so surrounding files never leak into a verdict —
see the vault Finding *gui-claude-subprocess-tcc-prompt*.

## Development philosophy

- **Incremental.** One small, self-contained slice per session.
- **Verify before moving on.** Every slice must be demonstrably working before the next starts.
- **Vault as the second brain.** Capture ideas, decisions, problems, and findings in `mynah-vault/`
  as we go. When something non-obvious is decided or discovered, write it down there.
- **Keep chat replies short.** Report what landed, what was verified, and anything that blocks —
  in a few lines. No long write-ups, no re-explaining reasoning already captured in the vault, no
  restating the diff in prose. The detail belongs in `mynah-vault/`; the reply just points at it.
  The developer asks when they want more on a specific point.

See `mynah-vault/Roadmap.md` for the phased plan and current status.

## The polish prompt (verbatim — do not paraphrase)

```
Fix the grammar and make the text sound more natural. Use simple technical English and a
warm, cozy tone. Provide only one revised version:
```
