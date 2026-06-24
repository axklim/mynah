# Roadmap — incremental plan

One small, **verifiable** slice per session. We don't design everything up front; we solve one
piece, prove it works, then move on. Check items off as they land and link to the session note
that delivered them.

## Phases

- [x] **Phase 0 — Foundation** *(this session, [[2026-06-23-session-01-foundation]])*
  CLAUDE.md, this vault, roadmap, and decision records. No app code. Verify by opening the
  vault in Obsidian.

- [x] **Phase 1 — CLI evaluator prototype (traffic light)** *(no Xcode needed,
  [[2026-06-23-session-02-cli-prototype]] · [[2026-06-24-session-03-traffic-light-evaluator]])*
  A `swift` command-line program in `cli/`, installed as `spell-checker` via `make install`:
  `spell-checker check <text>` (or stdin) → return **one** verdict 🔴 / 🟡 / 🟢
  ([[traffic-light-eval]]), no rewrite. **Comprehension-only red.** Backend
  is `claude -p --model sonnet` behind a `TextEvaluator` abstraction
  ([[0006-polish-backend-claude-cli]] · [[0007-traffic-light-evaluator-first]]) — **no API key
  needed**. Verified: clear → 🟢, error-heavy-but-clear → 🟡, ambiguous → 🔴.
  *(The polish/rewrite loop, pillar 1, is deferred to Phase 3.)*

- [ ] **Phase 2 — Menu bar shell + global hotkey** *(needs Xcode)*
  Status-item app that lives in the menu bar; a global hotkey opens an (empty) popup window.
  Verify: hotkey shows/hides the popup reliably.

- [ ] **Phase 3 — Wire the polish loop into the GUI**
  Input → Claude → one revised version → copy back. Implement the **"use my original / skip"**
  path. API key stored in Keychain via a settings screen.

- [ ] **Phase 4 — Mistake capture**
  Persist original vs. revised per polish; categorize mistake types via the LLM; store locally.
  See [[data-model]]. No UI surfacing yet — just reliable capture.

- [ ] **Phase 5 — Feedback dashboard**
  The larger window: common-mistakes overview + simple grammar explanations/rules driven by the
  developer's real data.

- [ ] **Phase 6 — Personal typo dictionary**
  Track frequent spelling/typing mistakes; show progress as they fade.

- [ ] **Phase 7 — Exercises**
  Generate small drills for the most frequent mistake topics.

## Backlog / later

- Local-only (offline) polishing mode.
- Tone presets beyond the default warm/cozy.
- History of past polishes with search.

## How we work

- Each phase = its own brainstorm (if needed) → plan → implement → verify cycle.
- Capture decisions in `Decisions/`, surprises in `Findings/`, open questions in
  [[open-questions]].
