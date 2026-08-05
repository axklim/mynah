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

- [x] **Phase 2 — Menu-bar evaluator (hotkey → verdict in the tray icon)**
  *(design: [[phase2-menubar-evaluator]] · [[2026-06-25-session-04-menubar-evaluator]])*
  Status-item app; **⌃⌥C** (rebound to **⌃⌥⌘C** in Phase 2.3) runs the [[traffic-light-eval|evaluator]] on the **clipboard** text and
  shows 🟢/🟡/🔴 (or ⚠️) in the icon for ~4s, then reverts. **No popup window** — the icon is the UI.
  Built with **SwiftPM + `make`**, no Xcode project (GUI frameworks ship with the CLT SDK —
  [[0003-build-toolchain-xcode-later]]). Reuses the evaluator via a shared `SpellCheckerCore`
  library. Verify: the flow works end-to-end (see the design's verification list).
  *(Reshaped from the original "hotkey opens an empty popup" — we pipe a real verdict into the
  icon instead; the rewrite/polish loop stays in Phase 3.)*

> **Distribution track (do before Phase 3).** Get the project onto a public remote and
> installable before adding more features — requested 2026-07-16.

- [ ] **Phase 2.1 — Publish to GitHub**
  Create the GitHub repository and push `main`. This is the prerequisite for the Homebrew tap in
  [[Roadmap|Phase 2.2]] (the formula points at a GitHub repo/release).

- [ ] **Phase 2.2 — Distribute via Homebrew**
  Ship `spell-checker` (and, if practical, the menu-bar app) through a Homebrew tap/formula so it
  installs with `brew install`. Depends on Phase 2.1.
  **Don't forget the font dependency.** The menu-bar icons are Nerd Font glyphs
  ([[0008-nerd-font-status-icons]]), so the app **cask** should declare
  `depends_on cask: "font-jetbrains-mono-nerd-font"` — or bundle `SymbolsNerdFont` in
  `Contents/Resources` and register it at launch, dropping the dependency. Confirm the cask DSL
  against Homebrew's docs then; a plain **formula** can't depend on a cask, so the CLI stays
  font-free (it prints emoji). The app falls back to emoji if the font is missing, so a miss here
  degrades rather than breaks.

- [x] **Phase 2.3 — Ad-hoc translator (En → Ru)** *(design: [[ad-hoc-translator]])*
  A second hotkey that translates the clipboard **English → Russian** into a floating window —
  for understanding what someone wrote *to* you, the mirror of the checker. Rebinds the checker to
  **Hyper+C** (⌃⌥⌘C); the translator is **Hyper+⇧C** (⌃⌥⌘⇧C). Word input (1–2 words) gets up to 3
  meanings with simple-English explanations and examples; longer text gets just the translation.
  Adds the shared input guards the checker never had (no text / over 2000 characters) and swaps the
  emoji icons for Nerd Font glyphs ([[0008-nerd-font-status-icons]]). All three verifiable slices
  have landed — guards + icons, `spell-checker translate`, and the floating window — and the whole
  feature was manually verified 2026-08-05. Not everything is settled: a handful of follow-ups from
  that pass, including one that would change shipped behaviour, are tracked in [[inbox]].
  *Was built **ahead of** the distribution track above (branch `ad-hoc-translator`, 2026-08-04);
  numbered after it to keep the phase numbers in order.*

> **Next up.** With Phase 2.3 done, the distribution track above — Phase 2.1 (GitHub) then Phase
> 2.2 (Homebrew) — is next, before Phase 3's polish loop.

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
