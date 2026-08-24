[![Release](https://github.com/axklim/mynah/actions/workflows/release.yml/badge.svg)](https://github.com/axklim/mynah/actions/workflows/release.yml)
[![version](https://img.shields.io/github/v/release/axklim/mynah?label=version)](https://github.com/axklim/mynah/releases)

# Mynah

A native macOS app that helps a non-native English speaker send clear, natural messages —
and quietly learns from recurring mistakes to teach better English over time.

Two pillars:

- **Polish loop** — global hotkey → popup → polish a message with Claude → copy it back
  (with an option to keep your original when it's already good).
- **Feedback & learning** — records mistakes over time and later surfaces a common-mistakes
  overview, grammar rules, small exercises, and a personal typo dictionary.

## Try it

A first prototype lives in [`cli/`](cli/README.md): a `mynah check` command that rates
a message 🔴 / 🟡 / 🟢 (no rewrite yet).

The CLI also translates between a configured language pair, defaulting to **English → German** —
`mynah translate "<text>"` — returning up to three meanings for a single word or short phrase, or
just the translation for anything longer. See [`cli/`](cli/README.md#configuration) for how to
change the pair.

```sh
brew install axklim/tap/mynah

mynah check "i has finished the task and it works good"
```

That installs **both halves** — the CLI and the menu-bar app — prebuilt, Apple silicon only.
Start the app with `brew services start mynah`, then press **⌃⌥⌘C** (Hyper+C) to rate whatever's
on the clipboard; the tray icon shows the verdict for a few seconds. A second hotkey
(**⌃⌥⌘⇧C**) translates the clipboard between the configured pair (default **English → German**)
into a floating window, for understanding what someone wrote to you. See [`cli/`](cli/README.md).

Or build it yourself:

```sh
make install      # builds + installs `mynah` to ~/.local/bin
make run-app      # builds + opens the menu-bar app
```

Needs an authenticated `claude` CLI — no API key. The CLI builds with the Swift Command Line
Tools; the menu-bar app needs full Xcode, because a dependency uses `#Preview`
(`mynah-vault/Findings/preview-macro-needs-xcode.md`) — which is why Homebrew ships prebuilt
artifacts instead of building from source (`mynah-vault/Decisions/0011-homebrew-tap-prebuilt.md`).

## Where the knowledge lives

Project knowledge — vision, decisions, designs, problems, and findings — lives in an
**Obsidian vault** at [`mynah-vault/`](mynah-vault/Home.md). Open that folder as a vault in Obsidian, or
start at `mynah-vault/Home.md`. See [`CLAUDE.md`](CLAUDE.md) for a quick orientation.

## Status

Early. Phases 1–2.3 have shipped: the CLI evaluator (installable via `make install`), a menu-bar
app that rates the clipboard on a global hotkey (**⌃⌥⌘C**) and shows a green / yellow / red dot in
the menu bar, and a second hotkey (**⌃⌥⌘⇧C**) that translates the clipboard into a floating window
— see [`cli/`](cli/README.md). Roadmap & current status: `mynah-vault/Roadmap.md`.
