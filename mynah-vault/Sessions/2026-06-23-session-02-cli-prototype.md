# Session 02 — CLI polish prototype (2026-06-23)

## Goal

Deliver [[Roadmap|Phase 1]]: a `swift` CLI that reads text, polishes it via the verbatim
[[polish-prompt]], and prints **one** revised version. Verify end-to-end.

## Key decision this session

The developer is on a **company Claude Code account** with no separate Anthropic API key to
issue, so the planned direct-API approach isn't available. We switched the backend to
**`claude -p --model haiku`** and put it behind a `PolishProvider` abstraction so a future
**litellm / Gemini** backend is a localized swap. Recorded as
[[0006-polish-backend-claude-cli]] (amends [[0001-llm-provider-claude]]).

## What we did

- Confirmed the current Haiku model is `claude-haiku-4-5` (alias `haiku`).
- Verified `claude -p --model haiku` + the verbatim polish prompt returns one clean revision.
- Built a SwiftPM executable in `cli/` (package `PolishCLI`, binary `polish`):
  - `PolishProvider.swift` — protocol + the verbatim prompt constant.
  - `ClaudeCLIProvider.swift` — shells out to `claude -p` via `Process`, feeds the prompt on
    stdin, reads **stdout only** (stderr discarded — it can carry unrelated global-hook noise).
  - `main.swift` — reads message from args or stdin, prints the revised text.
- Set `platforms: [.macOS(.v13)]` in `Package.swift` (needed for `FileHandle.close()`).

## Verified

- `swift build` succeeds.
- `swift run polish "i has finished the task ..."` → clean revised sentence.
- `echo "..." | swift run polish` (stdin/pipe form) → clean revised sentence.
- Output contains only the revision (no preamble, no harness noise).

## Notes / gotchas

- `claude -p` boots the full Claude Code harness (system prompt, tools, skills, MCP, hooks),
  so it's slower/heavier than a raw API call — fine for the prototype, a concern for the
  "daily, fast" loop (tracked in [[0006-polish-backend-claude-cli]]).
- A stray `SessionEnd` hook from the user's `second-brain` project errors to stderr on every
  `claude -p` call; harmless here because we only read stdout.
- Not committed yet — repo is on `main`; committing needs a feature branch first.

## Next step

Either: (a) commit Phase 1 on a feature branch, or (b) start **Phase 2 — menu bar shell +
global hotkey** (needs Xcode, not yet installed — see [[0003-build-toolchain-xcode-later]]).
Phase 2 is the natural next slice but is blocked on installing Xcode.
