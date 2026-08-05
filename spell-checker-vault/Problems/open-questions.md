# ❓ Open questions

Unresolved decisions and things to confirm. Move resolved ones into a `Decisions/` note.

## Product

- **App name** — working name is the repo name `spell-checker`. It's really a "message
  polisher + English coach," so the name may change. _Decide before any user-facing UI._

## LLM / cost

- **Exact Claude model IDs** for polish (Haiku) and analysis (stronger model) — confirm current
  IDs before Phase 1. (Use the `claude-api` reference rather than guessing.)
- **Rough per-message cost** — estimate so the developer knows the running cost of daily use.

## Privacy

- Polish requests send the developer's message text to **Anthropic**. Make this explicit in the
  UI/settings. Store all history **on-device**. Consider a later **local-only** mode
  ([[Roadmap]] backlog).

## Feedback system (Phase 4+)

- Categorize **every** polish vs. **batch** periodically (cost/latency trade-off)?
- Grammar rule library: **curated** vs. **LLM-generated** vs. **hybrid**?
- How to measure "**improving**" over time (decay window, streaks)?

## Build

- ~~When Xcode is installed: project as **Xcode `.xcodeproj`** vs. **SwiftPM-built `.app`**?~~
  **Resolved (2026-06-24):** SwiftPM + `make`, hand-assembled `.app` — no Xcode project. The GUI
  frameworks (AppKit, SwiftUI, Carbon) ship with the CLT SDK, so the build never depends on Xcode.
  See [[phase2-menubar-evaluator]] and [[0003-build-toolchain-xcode-later]].

## Related

[[Home]] · [[Spec]] · [[Roadmap]]
