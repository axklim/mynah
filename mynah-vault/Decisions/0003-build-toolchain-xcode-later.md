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

## Update (2026-06-24) — Xcode installed, but the build stays Xcode-free

Xcode 26.5 is now installed and is the active toolchain. **However**, we discovered the GUI
frameworks we need (AppKit, SwiftUI, Carbon, Cocoa) **already ship with the Command Line Tools
SDK**, and Swift 6.3 can build a menu-bar `.app` from a SwiftPM package. So for [[Roadmap|Phase
2]] we chose **SwiftPM + `make` with a hand-assembled `.app`** (`LSUIElement`) over an Xcode
`.xcodeproj` — keeping the whole project buildable from one `make`, with clean git and no Xcode
lock-in. Xcode stays available for when we genuinely want previews, asset catalogs, Instruments,
or App Store distribution; the **build does not depend on it**. See
[[phase2-menubar-evaluator]].

## Correction (2026-08-11) — "the build does not depend on it" is false for the app

The 2026-06-24 update above is right that AppKit, SwiftUI, Carbon and Cocoa ship in the CLT SDK,
and right about the CLI. It is **wrong that the build as a whole is Xcode-free**:
`swift build --product mynah-bar` fails against the CLT SDK, because the `KeyboardShortcuts`
dependency uses `#Preview` and that macro's plugin ships only inside Xcode. Measured both ways in
[[preview-macro-needs-xcode]].

The claim was never wrong about what it checked — the *frameworks*. The requirement arrived later,
with a third-party dependency, and went unnoticed because `xcode-select -p` points at Xcode here, so
every local build had silently used Xcode's SDK. Read the update above as: **CLT-only holds for the
`mynah` CLI and for our own AppKit/SwiftUI code; `mynah-bar` needs Xcode until the dependency
changes.** This is what limited [[Roadmap|Phase 2.2]] to shipping the CLI
([[0010-homebrew-formula-cli-only]]).

## Related

[[Roadmap]] · [[toolchain-notes]] · [[0004-incremental-foundation-first]] · [[phase2-menubar-evaluator]] ·
[[preview-macro-needs-xcode]] · [[0010-homebrew-formula-cli-only]]
