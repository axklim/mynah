# 💡 Idea inbox

Quick capture. Drop half-formed ideas here without ceremony; promote the good ones into
[[Spec]], [[Roadmap]], or a Design note later. Delete once promoted or rejected.

## Inbox

- **Shortcut recorder UI** — let the user rebind the global hotkey from a settings screen,
  instead of the hardcoded default (⌃⌥⌘C). `KeyboardShortcuts` ships a `Recorder` view for
  exactly this; wire it in when we build settings (likely [[Roadmap|Phase 3]]).
- **History + cache for instant repeats** — keep a history of checked payloads and their
  verdicts. The [[Roadmap|Phase 2]] icon shows a result for only 3–5s, so if the user glances
  away they miss it. If the user re-triggers on the **same payload**, answer **immediately** from
  the cache instead of re-calling Claude (faster + cheaper). Foundation for the feedback/learning
  pillar too. Related edge case: [[concurrent-recheck-while-busy]].
- **Richer text input for the evaluator** — [[Roadmap|Phase 2]] reads the **clipboard** only. Add
  better sources later: the **current selection** (no copy step), or a **typed-in popup** where
  the user pastes/edits before checking. The popup also unlocks pillar 1 (the rewrite/polish
  loop). See the input TODO in [[phase2-menubar-evaluator]].
- **Clickable "more…" in the translator** — word mode shows up to 3 meanings and a passive "more
  meanings exist" line when the word has others ([[ad-hoc-translator]]). Make it expand the window
  with the remaining meanings — either ask Claude for all of them up front (slower, mostly wasted)
  or fire a second call on click. Deliberately deferred to keep the first version simple.
- **Try Haiku for the translator's text mode** — both modes default to Sonnet, matching the
  evaluator ([[haiku-misses-ambiguity]]). Plain text translation is an easier task than the word
  mode's explanations, and speed matters for a window you're staring at. One-line experiment once
  the prompts settle ([[ad-hoc-translator]]).
- **Copy affordance for translation results** — the window's text is selectable (⌘C works) but has
  no copy button and no auto-copy; the need was genuinely unclear at design time. Revisit once real
  use says something.
- **Ru → En autodetection** — the translator is En → Ru only by decision; pasting Russian is
  undefined. Add direction detection if it starts to itch ([[ad-hoc-translator]]).
- **Sort out `Ideas/Draft.md`** — it holds raw personal drafts/notes (vault naming, session-start
  behaviour, where notes/todos should live). Review them, promote anything worth keeping into
  [[Spec]], [[Roadmap]], a Design note, or a proper inbox item above, then trim the file.
  Requested 2026-07-16.

## Promoted / parked

- Tone presets beyond warm/cozy → parked in [[Roadmap]] backlog.
- Local-only offline polishing → parked in [[Roadmap]] backlog.
- History of past polishes with search → parked in [[Roadmap]] backlog.
