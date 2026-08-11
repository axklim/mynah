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
| Distribution    | `brew install axklim/tap/mynah` builds the **CLI** from source; the formula lives in the `axklim/homebrew-tap` repo, not here (Decision 0010). App distribution is unsolved. |
| Secrets         | Keychain (future GUI). The CLI evaluator needs no API key — it shells out to an authed `claude -p` (Decision 0006) |
| Storage         | Local, on-device (message text is sensitive — see Privacy in vault)      |

## Building & running

The code lives in `cli/` (a SwiftPM package) and builds two products (binary names are lowercase
and may contain hyphens; module names are CamelCase and can't — see `cli/Package.swift`):

- **`mynah`** (target `Mynah`) — the CLI evaluator.
- **`mynah-bar`** (target `MynahBar`) — the Phase 2 menu-bar app.

CLI targets:

- `brew install axklim/tap/mynah` — the installed path for the CLI (see Decision 0010)
- `make install` — build release + install `mynah` to `~/.local/bin` (override `PREFIX=…`).
  Pass `SWIFT_FLAGS=…` to add `swift build` flags; the formula uses it for `--disable-sandbox`,
  since a Homebrew build can't nest SwiftPM's own sandbox.
- `make build` / `make uninstall` / `make clean`; bare `make` prints the target list
- Dev without installing: `cd cli && swift run mynah check "some text"`
- Run it: `mynah check "<text>"` (or `pbpaste | mynah check`) → one verdict 🔴/🟡/🟢
- Translate it: `mynah translate "<text>"` (or `pbpaste | mynah translate`) —
  **English → Russian only**, no autodetection. One or two words return up to three meanings, each
  with a simple-English explanation and an example; three or more words return just the translation.

**Menu-bar app (Phase 2).** `mynah-bar` is an `LSUIElement` accessory app (no Dock icon):
the global hotkey **⌃⌥⌘C** (Hyper+C) (via the `KeyboardShortcuts` package) evaluates the clipboard text and
shows the verdict in the status-item icon for ~4s, then reverts: a green / yellow / red dot, an
outlined page when the clipboard has no text, a book when the text is over 2000 characters, or a
warning triangle on failure.

**⌃⌥⌘⇧C** (Hyper+⇧C) translates the clipboard **English → Russian** into a floating window —
one or two words return up to three meanings with simple-English explanations, longer text returns
just the translation. Esc or clicking away dismisses it and cancels the call. The window is the UI
for this feature, so input problems appear as sentences in it rather than as icon states.

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

See `mynah-vault/Roadmap.md` for the phased plan and current status.

## The polish prompt (verbatim — do not paraphrase)

```
Fix the grammar and make the text sound more natural. Use simple technical English and a
warm, cozy tone. Provide only one revised version:
```
