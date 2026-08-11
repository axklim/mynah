# Session 03 — Traffic-light evaluator (2026-06-24)

## Goal

Pivot the first prototype from a **rewriter** to an **evaluator**: read text → return one
traffic-light verdict (🔴 / 🟡 / 🟢), nothing else. (Continues [[2026-06-23-session-02-cli-prototype]].)

## What we did

- Brainstormed the change. Landed on: **evaluation only** (no rewrite), output is **one signal**
  — red / yellow / green — and **red is comprehension-only**.
- Recorded the pivot as [[0007-traffic-light-evaluator-first]]; criteria in
  [[traffic-light-eval]].
- Repurposed the `cli/` prototype: `PolishProvider` → `TextEvaluator`, `polish` binary →
  **`check`**, polish prompt → evaluation prompt. Added a `Verdict` enum and lenient parsing.
- **Model: switched to Sonnet** after a finding that Haiku misses ambiguity
  ([[haiku-misses-ambiguity]]).
- **Tuned the prompt to comprehension-only** after Sonnet first over-flagged an error-heavy but
  clear message as red.

## Verified

- `swift build` clean. `check` works via arg and stdin.
- clear → 🟢 green · error-heavy-but-clear → 🟡 yellow · ambiguous double-meaning → 🔴 red.

## Notes

- The `claude -p` backend + provider abstraction from [[0006-polish-backend-claude-cli]] carried
  over unchanged (protocol renamed `TextEvaluator`).
- The polish/rewrite loop (pillar 1) is deferred to the GUI ([[Roadmap|Phase 3]]).
- Still **not committed** — repo is on `main`; committing needs a feature branch first.

## Next step

Commit Phase 1 (evaluator) on a feature branch, **or** start [[Roadmap|Phase 2]] — menu bar
shell + global hotkey — which needs **Xcode** (not yet installed,
[[0003-build-toolchain-xcode-later]]).
