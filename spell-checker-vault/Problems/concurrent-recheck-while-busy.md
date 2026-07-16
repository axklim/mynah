# ⚠️ Edge case — hotkey pressed while a check is already running

The menu-bar evaluator ([[Roadmap|Phase 2]]) runs an async `claude -p` call that takes a few
seconds. What happens if the user presses **⌃⌥C** again *before* the in-flight check finishes?

## Decision for now (Phase 2)

**Ignore the re-press.** While a check is in flight (icon in the "working" ⏳ state), additional
hotkey presses are dropped — **no overlapping runs**. Simplest correct behaviour; avoids racing
icon updates.

## Likely better behaviour later

**Cancel-first, process-last.** A fresh press should *cancel* the running check and start a new
one on the latest clipboard payload. Rationale: if the user re-triggers, they almost certainly
want the result for *what they just copied*, not the stale earlier payload. Showing a verdict for
old text would be confusing.

Revisit when the polish loop / richer input lands. Related: [[history-cache-instant-repeat]]
(a cache could make a repeat press on the *same* payload answer instantly instead of re-running).

## Related

[[Home]] · [[Roadmap]]
