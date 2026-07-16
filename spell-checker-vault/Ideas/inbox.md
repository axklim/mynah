# 💡 Idea inbox

Quick capture. Drop half-formed ideas here without ceremony; promote the good ones into
[[Spec]], [[Roadmap]], or a Design note later. Delete once promoted or rejected.

## Inbox

- **Shortcut recorder UI** — let the user rebind the global hotkey from a settings screen,
  instead of the hardcoded default (⌃⌥C). `KeyboardShortcuts` ships a `Recorder` view for
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

## Promoted / parked

- Tone presets beyond warm/cozy → parked in [[Roadmap]] backlog.
- Local-only offline polishing → parked in [[Roadmap]] backlog.
- History of past polishes with search → parked in [[Roadmap]] backlog.
