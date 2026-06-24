# spell-checker — CLI evaluator (Phase 1)

Evaluates a message and returns **one** traffic-light verdict — 🔴 / 🟡 / 🟢 — and nothing else.
It does not rewrite the text.

- 🟢 **green** — clear, natural, safe to send as is.
- 🟡 **yellow** — understandable, but worth fixing (awkward / non-native / grammar slips).
- 🔴 **red** — a reader might misunderstand it (unclear, ambiguous, or a double meaning).

`red` is **comprehension-only**: grammar mistakes alone stay yellow as long as the meaning is
clear. Criteria + prompt:
[traffic-light-eval](../spell-checker-vault/Design/traffic-light-eval.md).

Backend: `claude -p --model sonnet` (Claude Code CLI in print mode) behind a `TextEvaluator`
abstraction — no API key needed. See
[Decision 0006](../spell-checker-vault/Decisions/0006-polish-backend-claude-cli.md) and
[Decision 0007](../spell-checker-vault/Decisions/0007-traffic-light-evaluator-first.md).

## Requirements

- Swift 6 toolchain (Command Line Tools is enough — no Xcode).
- The `claude` CLI installed and authenticated (`claude -p` must work).

## Install

From the repo root:

```sh
make install          # builds release, installs `spell-checker` to ~/.local/bin
```

Override the location with `make install PREFIX=/usr/local`; remove with `make uninstall`.

## Usage

```sh
spell-checker check "Please send the file to Anna and her assistant when she is ready."
# → 🔴 red

pbpaste | spell-checker check
echo "Thanks for the review, I've merged the branch." | spell-checker check
# → 🟢 green

spell-checker --help
```

Prints just the verdict to stdout; errors go to stderr with a non-zero exit code.

## Dev (without installing)

```sh
cd cli && swift run spell-checker check "some text"
```

## Swapping the backend later

Implement another `TextEvaluator` (e.g. a litellm / Gemini backend) and use it in `main.swift`.
Nothing else changes.
