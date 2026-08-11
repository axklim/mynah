# 🔎 Finding — local toolchain & environment

Captured 2026-06-23 on the developer's machine.

## Environment

- **macOS:** 26.4.1 (build 25E253), **Apple Silicon** (`arm64`).
- **Swift:** 6.3.2 (`swiftlang-6.3.2.1.108`), via **Command Line Tools** at
  `/Library/Developer/CommandLineTools`.
- **Xcode:** **not installed.** `xcodebuild` errors out — only CLT is the active developer dir.
- **Obsidian:** installed at `/Applications/Obsidian.app`.

## Implications

- The `swift` CLI **can compile and run** command-line Swift today → Phase 1 (CLI polish
  prototype) is viable without Xcode.
- GUI work (menu bar, SwiftUI, global hotkey, `.app` bundling, signing/entitlements) is far
  smoother with Xcode → blocked on installing it (Phase 2+). See
  [[0003-build-toolchain-xcode-later]].
- **Global hotkey** plan: Carbon `RegisterEventHotKey` does **not** require Accessibility
  permission (a `CGEventTap` would). Good default for [[0002-invocation-menubar-hotkey]].

## When installing Xcode later

- Install from the App Store, then point the toolchain at it:
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- Re-check `xcodebuild -version`.

## Related

[[Roadmap]] · [[0003-build-toolchain-xcode-later]]
