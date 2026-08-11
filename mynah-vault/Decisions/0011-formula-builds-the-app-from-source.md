# 0011 — The formula builds the menu-bar app from source, patching the previews out

- **Status:** accepted — supersedes the app half of [[0010-homebrew-formula-cli-only]]
- **Date:** 2026-08-11
- **Relates to:** [[0010-homebrew-formula-cli-only]] · [[preview-macro-needs-xcode]] ·
  [[0003-build-toolchain-xcode-later]] · [[gui-claude-subprocess-tcc-prompt]] · [[Roadmap|Phase 2.2]]

## Context

`brew install axklim/mynah/mynah` gave the CLI and a caveat that read, in full, *"the menu-bar app
is not installed by this formula; building it needs full Xcode. Clone the repo and run `make app`
for now."* The app is the daily driver, so the formula was shipping the wrong half and telling the
user to go build the rest themselves.

[[0010-homebrew-formula-cli-only]] left three routes open and picked none. Its update called a
**prebuilt bundle installed by a formula** the most promising — CI already publishes
`mynah-app-<version>.zip` for exactly that. This decision takes a different one.

**The blocker was three lines of dead code in a dependency.** [[preview-macro-needs-xcode]]
established that `mynah-bar` cannot compile against the Command Line Tools SDK because
`KeyboardShortcuts` ends `Recorder.swift` with three `#Preview` blocks and the `Preview` macro is
implemented only inside Xcode. Measured again while deciding this: deleting those blocks makes
`mynah-bar` build against the CLT SDK in **7.6 s**, and the macro was the *only* Xcode-only
construct in the whole app — nothing in our own AppKit/SwiftUI code needs Xcode, which is what
[[0003-build-toolchain-xcode-later]] originally claimed and had half-verified. We never use
`KeyboardShortcuts.Recorder`, so for this project the previews are dead code.

## Decision

**The formula builds both products from source, and `make app` patches the previews out of the
pinned checkout before compiling.**

Three pieces:

1. **`cli/packaging/strip-preview-macros.sh`** truncates `Recorder.swift` at its first `#Preview`
   and re-closes the trailing `#if os(macOS)`. It is idempotent (a second run finds nothing), and
   it **verifies the file's sha256 before touching it** — patching a third party's source is only
   safe when you know precisely which source it is.
2. **`Package.swift` pins `KeyboardShortcuts` `exact: "1.17.0"`**, not `from: "1.9.0"`. This is the
   load-bearing half of the safety: `Package.resolved` is gitignored, so under `from:` every user
   would resolve whatever was newest that day and the patch would aim at a moving file. Under
   `exact:` plus the checksum, a dependency bump **fails the build with an explanation** instead of
   silently mangling a file.
3. **The formula runs `make install` then `make app`** and does `prefix.install "cli/dist/Mynah.app"`,
   plus a `service do` block so `brew services start mynah` runs it at login.

**Why from-source and not the prebuilt zip.** Both work, and the zip is one download versus a
~20 s compile. From-source wins on two counts: it keeps *one* artifact per release instead of a
formula whose contents depend on a CI job having produced a matching asset, and it makes
`brew install --HEAD` install a real app rather than the last release's bundle. The zip route also
has to keep proving the non-obvious quarantine claim from [[0010-homebrew-formula-cli-only]];
locally compiled output is never quarantined, which needs no argument.

## Verified

Not assumed — an end-to-end `brew install --build-from-source` of the working tree, as a keg-only
formula so it could not disturb the real install:

- `make app` runs inside the Homebrew sandbox, `codesign --sign -` included.
- `brew test` passes, including two new assertions that the bundle's executable is installed and
  its generated `Info.plist` carries the release version — a bundle whose `__VERSION__`
  substitution silently failed would still "exist".
- `brew audit --strict` is clean.
- The installed bundle carries **no `com.apple.quarantine` attribute**, keeps its ad-hoc signature
  (`Identifier=io.klimov.mynah`, `Signature=adhoc`), and **launches** out of the Cellar.
- The checksum tripwire fires as intended on a modified `Recorder.swift`, and the patch is a no-op
  on a second run.

## Consequences

- `brew install axklim/mynah/mynah` now installs **both** the CLI and `Mynah.app`, on a machine
  with the Command Line Tools alone. Phase 2.2's real goal is met.
- **Install time grows** by the app build. The whole from-source install, both products, measured
  **19 s** on this machine — the cost is not worth optimising.
- **`KeyboardShortcuts` no longer updates on its own.** That is the point, but it means security or
  compatibility bumps are a manual step that now also requires re-reading `Recorder.swift` and
  updating the checksum. The script says so when it fails.
- **The release zip is now redundant.** `mynah-app-<version>.zip` in CI is a second way to get the
  same bundle; it is left in place for direct downloads, but nothing installs from it. Removing it
  is a follow-up, not a requirement.
- **Upgrades will likely re-prompt for permission.** The service runs `opt_prefix`, which keeps the
  launch agent's command stable, but launching resolves to the versioned Cellar path (measured) and
  the bundle is only ad-hoc signed — so macOS may treat each upgrade as a new app. See
  [[gui-claude-subprocess-tcc-prompt]]. Unsolved, and cheap to live with.
- **The font question stays open.** [[0008-nerd-font-status-icons]]: without JetBrainsMono Nerd
  Font the app falls back to emoji, and a formula cannot depend on a cask. Now that the app ships,
  this is a real user-facing rough edge rather than a hypothetical.
- If `KeyboardShortcuts` ever becomes a burden, the durable fix is still to drop it for a direct
  Carbon `RegisterEventHotKey` call — the library is a thin wrapper over exactly that, and we use
  two fixed shortcuts and no `Recorder` UI.

## Related

[[0010-homebrew-formula-cli-only]] · [[preview-macro-needs-xcode]] · [[Roadmap]] · [[Home]]
