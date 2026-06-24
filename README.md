# spell-checker

A native macOS app that helps a non-native English speaker send clear, natural messages —
and quietly learns from recurring mistakes to teach better English over time.

Two pillars:

- **Polish loop** — global hotkey → popup → polish a message with Claude → copy it back
  (with an option to keep your original when it's already good).
- **Feedback & learning** — records mistakes over time and later surfaces a common-mistakes
  overview, grammar rules, small exercises, and a personal typo dictionary.

## Try it (CLI)

A first prototype lives in [`cli/`](cli/README.md): a `spell-checker check` command that rates
a message 🔴 / 🟡 / 🟢 (no rewrite yet).

```sh
make install      # builds + installs `spell-checker` to ~/.local/bin
spell-checker check "i has finished the task and it works good"
```

Needs a Swift 6 toolchain and an authenticated `claude` CLI — no API key.

## Where the knowledge lives

Project knowledge — vision, decisions, designs, problems, and findings — lives in an
**Obsidian vault** at [`spell-checker-vault/`](spell-checker-vault/Home.md). Open that folder as a vault in Obsidian, or
start at `spell-checker-vault/Home.md`. See [`CLAUDE.md`](CLAUDE.md) for a quick orientation.

## Status

Early. Phase 1 (the CLI evaluator) has shipped and is installable — see
[`cli/`](cli/README.md). Roadmap & current status: `spell-checker-vault/Roadmap.md`.
