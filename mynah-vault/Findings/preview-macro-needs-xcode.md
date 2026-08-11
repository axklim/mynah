# Finding — the menu-bar app needs full Xcode, not just the CLT

- **Date:** 2026-08-11
- **Found while:** building the Homebrew formula for [[Roadmap|Phase 2.2]]
- **Relates to:** [[0003-build-toolchain-xcode-later]] · [[0010-homebrew-formula-cli-only]]

## What we believed

[[0003-build-toolchain-xcode-later]] says the whole project builds with the Swift **Command Line
Tools** and `make`, no Xcode project and no Xcode. That was checked against the *frameworks* —
AppKit and SwiftUI do ship in the CLT SDK, which is what the decision actually verified.

## What is true

`swift build --product mynah-bar` **fails against the CLT SDK**:

```
error: external macro implementation type 'PreviewsMacros.SwiftUIView' could not be found
for macro 'Preview(_:body:)'; plugin for module 'PreviewsMacros' not found
```

The `KeyboardShortcuts` dependency (1.17.0) ends `Recorder.swift` with three `#Preview` blocks,
guarded only by `#if os(macOS)` — so they compile in every configuration, including release. The
`Preview` macro is *declared* in SwiftUI (present in the CLT SDK) but *implemented* by
`libPreviewsMacros.dylib`, which exists only inside Xcode:

```
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libPreviewsMacros.dylib
```

`find /Library/Developer/CommandLineTools -name '*PreviewsMacros*'` returns nothing.

Measured on this machine, with the SDK as the only variable:

| target | CLT SDK | Xcode SDK |
|--------------------|--------------------------|-----------|
| `mynah` (CLI) | builds | builds |
| `mynah-bar` (app) | fails, as above | builds |

The CLI is unaffected because it depends on `MynahCore` only — it never compiles
`KeyboardShortcuts`. Nothing about this is Homebrew-specific: setting `SDKROOT` to the CLT SDK
reproduces it in a plain shell. Homebrew merely exposed it, because its build environment sets
`SDKROOT` to the CLT SDK while the toolchain is Xcode's `swiftc`.

## Why it stayed hidden

`xcode-select -p` on this machine points at `/Applications/Xcode.app`, so every local build has
silently used Xcode's SDK. The requirement arrived with a **third-party dependency**, not with
project code, so no decision was ever made about it and nothing in the repo mentions it.

## Consequences

- **Distribution.** A formula that built the app from source would force every user to install
  Xcode (~10 GB) to get a menu-bar utility. That is why [[0010-homebrew-formula-cli-only]] ships
  the CLI alone.
- **`make build` was scoped to the CLI product.** It previously built *every* target, so
  `make install` — which installs only `mynah` — compiled `MynahBar` and `KeyboardShortcuts` too,
  dragging this Xcode requirement into the CLI path for no benefit. It now passes
  `--product mynah`, matching its own help text ("the release binary") and `make app`'s existing
  `--product` scoping.
- **[[0003-build-toolchain-xcode-later]] needs reading with this caveat**: CLT-only is true for
  the CLI and for the project's own AppKit/SwiftUI code, not for `mynah-bar` as it stands.
- **If CLT-only for the app ever matters**, the options are to drop `KeyboardShortcuts` for a
  direct Carbon `RegisterEventHotKey` call (the library is a thin wrapper over it), or to patch
  the previews out of the checkout at build time. Neither is worth doing today.

## Related

[[0010-homebrew-formula-cli-only]] · [[0003-build-toolchain-xcode-later]] · [[Roadmap]]
