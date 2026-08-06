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
  Phase 2.3's floating panel (`TranslationPanel` + `TranslationView`) is a working starting point
  for that popup — it already handles Esc/focus-loss dismissal, cancellation of an in-flight call,
  and placement, so the polish loop mainly needs an editable input instead of a read-only result.
- **Clickable "more…" in the translator** — word mode shows up to 3 meanings and a passive "more
  meanings exist" line when the word has others ([[ad-hoc-translator]]). Make it expand the window
  with the remaining meanings — either ask Claude for all of them up front (slower, mostly wasted)
  or fire a second call on click. Deliberately deferred to keep the first version simple.
- **Try Haiku for the translator's text mode** — both modes default to Sonnet, matching the
  evaluator ([[haiku-misses-ambiguity]]). Plain text translation is an easier task than the word
  mode's explanations, and speed matters for a window you're staring at. One-line experiment once
  the prompts settle ([[ad-hoc-translator]]).
- **Ru → En autodetection** — the translator is En → Ru only by decision; pasting Russian is
  undefined. Add direction detection if it starts to itch ([[ad-hoc-translator]]).
- **Defer opening the translation window until the result is ready** — requested 2026-08-05 after
  the manual verification pass of [[ad-hoc-translator|Phase 2.3]]. Today `runTranslate` opens the
  panel in `.loading` immediately; the ask is for the 文A glyph in the menu bar to be the only
  "working" signal, with the window appearing only once there is something to read.
  **The tension, and it's not obvious:** the panel is currently the *only* trigger for cancelling
  an in-flight call — Esc or focus loss calls `TranslationHandle.cancel()`. With no window during
  the wait there is nothing to dismiss, so cancellation loses its trigger entirely. Whoever
  implements this must either add a new one (pressing Hyper+⇧C again to cancel, or a "Cancel
  translation" menu item) or knowingly accept that the handle and generation counter sit inert
  until one exists. **Do not delete that machinery as dead code** — it solves a real problem (a
  subprocess outliving its window) and was verified to work.
- **Show each hotkey in the status-item menu** — requested 2026-08-05 with a screenshot: "Check
  clipboard now" and "Translate clipboard now" show no key equivalent, while "Quit Mynah"
  displays ⌘Q and carries an icon. Set `keyEquivalent` and `keyEquivalentModifierMask` on both
  items so the menu documents the shortcuts (⌃⌥⌘C and ⌃⌥⌘⇧C), and give each an image the way Quit
  already has one. Note: setting a key equivalent on a status-item menu item also makes it live
  while the menu is open — harmless here, since the global hotkeys already do the same thing.
- **Copy affordance for the translation window — reopened, ⌘C doesn't work** — the window's text is
  selectable but has no copy button, no auto-copy, and — found during the
  [[ad-hoc-translator|Phase 2.3]] manual verification pass — **⌘C does not actually copy it**.
  Likely cause, recorded so nobody repeats the investigation: `.textSelection(.enabled)` makes text
  selectable, but ⌘C needs a responder handling the `copy:` action, and in a normal app that routing
  comes from the main menu's Edit → Copy item. This app is `LSUIElement` with only a status-item
  menu and no application main menu at all, so the keystroke has nowhere to go. Two candidate fixes:
  install a minimal main menu with an Edit menu containing Copy, or handle `copy:` in the
  panel/hosting view directly. The design's "no copy button, selection is enough" decision
  ([[ad-hoc-translator]]) **depended on ⌘C working for free — it doesn't**, so that decision is
  reopened until one of the fixes lands: a plain copy button is back on the table, not something
  already ruled out.
- **Polish command — pillar 1 filed with a worked example** — requested 2026-08-06. Run the
  fixed polish prompt (verbatim in `CLAUDE.md`) over the input text and return **one** revised
  version:
  > Fix the grammar and make the text sound more natural. Use simple technical English and a
  > warm, cozy tone. Provide only one revised version: `<text>`

  This is [[Roadmap|Phase 3]]'s polish loop; this entry pins the expected behaviour with a real
  example. A first verifiable slice could be `mynah polish` (mirroring `translate`),
  with the GUI wiring after.
  **Worked example.** Input:
  > I'm going to deploy: https://github.com/ozean12/refinancing/pull/1597 (hold fundings as a list on the invoice aggregate) and will monitor it tomorrow morning :slightly_smiling_face:

  Expected output:
  > I'm going to deploy https://github.com/ozean12/refinancing/pull/1597 (hold fundings as a list on the invoice aggregate) and will monitor it tomorrow morning. 🙂

  Note what "natural" means here beyond grammar: the stray colon before the URL goes, a period
  lands at the end of the sentence, and the Slack-style `:slightly_smiling_face:` shortcode
  becomes a real emoji 🙂 — the polish should clean up chat-isms too.
- **Sort out `Ideas/Draft.md`** — it holds raw personal drafts/notes (vault naming, session-start
  behaviour, where notes/todos should live). Review them, promote anything worth keeping into
  [[Spec]], [[Roadmap]], a Design note, or a proper inbox item above, then trim the file.
  Requested 2026-07-16.

## Promoted / parked

- Tone presets beyond warm/cozy → parked in [[Roadmap]] backlog.
- Local-only offline polishing → parked in [[Roadmap]] backlog.
- History of past polishes with search → parked in [[Roadmap]] backlog.
