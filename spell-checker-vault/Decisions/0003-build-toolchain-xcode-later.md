# 0003 — Build toolchain: Swift/SwiftUI, Xcode installed later

- **Status:** accepted
- **Date:** 2026-06-23

## Context

Only the Command Line Tools are installed (`swift` 6.3.2), not full Xcode. A menu-bar SwiftUI
app with a global hotkey is normally built and run through Xcode. The developer chose to
**install Xcode later** rather than now or going Xcode-free permanently.

## Decision

Target **Swift 6 / SwiftUI + AppKit**, built with **Xcode** — but **defer installing Xcode**.
Until it's installed, only do work that is verifiable with the existing CLT `swift` toolchain.

## Why

- SwiftUI/AppKit is the idiomatic native path; Xcode gives previews, bundling, signing,
  entitlements with the least friction.
- Deferring the large Xcode download lets us make real, verifiable progress now (foundation,
  then a CLI prototype of the LLM core).

## Consequences

- **Phase 0–1** are intentionally Xcode-free (docs + a `swift` CLI prototype).
- **Phase 2+** (the GUI) are blocked until Xcode is installed.
- When ready: install Xcode from the App Store, then `sudo xcode-select -s` to point at it.

## Related

[[Roadmap]] · [[toolchain-notes]] · [[0004-incremental-foundation-first]]
