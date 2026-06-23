# 🏠 Home — spell-checker vault

This vault is the **second brain** and single source of truth for the project. Everything we
decide, wonder about, or discover lives here. Future sessions start by reading this note.

## What we're building

A **native macOS app** that helps a non-native English speaker send clear, natural messages,
and learns from their recurring mistakes to teach better English over time. Full detail in
[[Spec]].

### Two pillars

1. **Polish loop** — global hotkey → popup → polish with Claude → copy back (with a
   "use my original / skip" option).
2. **Feedback & learning** — silently records mistakes, later surfaces overviews, grammar
   rules, exercises, and a personal typo dictionary.

## Map of content

- 📜 [[Spec]] — the living product spec
- 🗺️ [[Roadmap]] — phased, incremental plan + current status
- 🧠 **Design**
  - [[polish-prompt]] — the exact prompt and tuning notes
  - [[feedback-system]] — how mistakes are captured, categorized, and taught
  - [[data-model]] — how mistake events & typos are stored
- ✅ **Decisions** (ADR-style)
  - [[0001-llm-provider-claude]]
  - [[0002-invocation-menubar-hotkey]]
  - [[0003-build-toolchain-xcode-later]]
  - [[0004-incremental-foundation-first]]
  - [[0005-obsidian-vault-as-source-of-truth]]
- ❓ [[open-questions]] — unresolved decisions
- 💡 [[inbox]] — quick idea capture
- 🔎 [[toolchain-notes]] — environment findings
- 📓 **Sessions** — [[2026-06-23-session-01-foundation]]

## How to use this vault

- **Decisions** → `Decisions/` as small ADR notes (one decision each). Don't bury decisions in
  prose; give each its own note so it can be linked and revisited.
- **Ideas** → drop into [[inbox]] fast; promote good ones into Design or the Roadmap later.
- **Problems / edge cases / open questions** → `Problems/`.
- **Findings** (things we learned the hard way) → `Findings/`.
- **Session logs** → `Sessions/`, one per working session, ending with the next step.

Link liberally with `[[wikilinks]]` so the graph stays connected.
