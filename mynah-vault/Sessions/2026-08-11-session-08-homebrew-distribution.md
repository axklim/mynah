# Session 08 — Homebrew distribution (2026-08-11)

## Goal

[[Roadmap|Phase 2.2]]: make Mynah installable with `brew install`. Phase 2.1 turned out to be
already done — the repo is public at github.com/axklim/mynah — but was never checked off.

## What we did

Built and verified a Homebrew formula for the **CLI**, and discovered along the way that the
**app cannot ship this way at all**.

- **Approach chosen up front: formula building from source, not a cask.** `make app` only ad-hoc
  signs, and Homebrew quarantines cask downloads, so an un-notarized bundle would be Gatekeeper-
  blocked. Locally compiled binaries carry no quarantine flag. Recorded as
  [[0010-homebrew-formula-cli-only]].
- **A local tap** (`brew tap-new axklim/tap`) to develop against, with the formula tested from a
  release-shaped tarball built out of the working tree — so each iteration tested uncommitted code.
- **`Makefile` gained a `SWIFT_FLAGS ?=` seam**, and `build` was scoped to `--product mynah`.
- **`RELEASING.md` in the tap** with the tag-and-checksum procedure.

## Verified

- `brew install --build-from-source axklim/tap/mynah` installs `mynah` to the Cellar and onto PATH.
- `brew test mynah` passes; `brew audit --strict --formula` is silent.
- The **installed** binary, not the dev build, returned 🟡 for
  `mynah check "i has finished the task and it works good"` — end-to-end through Homebrew with the
  real `claude` backend.
- `make test` (51 tests, 0 failures), `make build`, `make app` all still fine after the Makefile
  change.

## Two failures worth remembering

**SwiftPM cannot nest its sandbox inside Homebrew's.** The first install died on
`Invalid manifest` with `sandbox-exec: sandbox_apply: Operation not permitted`. SwiftPM compiles
`Package.swift` inside its own `sandbox-exec`, and a brew build is already sandboxed. Fix:
`--disable-sandbox`, passed through the new `SWIFT_FLAGS` seam so local builds keep SwiftPM's
sandbox — it is a real safety feature, not ceremony.

**The app needs full Xcode, and always has.** Written up as [[preview-macro-needs-xcode]]. The
second install failed on `PreviewsMacros` not found: `KeyboardShortcuts` ends `Recorder.swift`
with `#Preview` blocks guarded only by `#if os(macOS)`, and that macro's plugin ships only inside
Xcode. Isolating `SDKROOT` in a plain shell proved the CLI builds against the CLT SDK and the app
does not — nothing Homebrew-specific. It stayed hidden because `xcode-select -p` here points at
Xcode, so every local build had quietly used Xcode's SDK. It also means
[[0003-build-toolchain-xcode-later]]'s CLT-only claim holds for the CLI and for our own
AppKit/SwiftUI code, but not for `mynah-bar` as it stands — and the requirement came from a
dependency, so no decision was ever taken about it.

That finding is what reduced Phase 2.2's scope: shipping the app from source would demand ~10 GB of
Xcode from every user.

## Notes

- **A self-inflicted detour worth not repeating.** Two runs failed on
  `No rule to make target 'install'` because the Bash tool's working directory persists between
  calls: a `cd cli` from an earlier command meant the "repo root" tarball was built from `cli/`, with
  no `Makefile` at top level. Build tarballs with an explicit absolute root.
- **`make build` used to build every target**, so `make install` compiled `MynahBar` and
  `KeyboardShortcuts` just to install `mynah` — slower, and it pulled the Xcode requirement into the
  CLI path. Now `--product mynah`, matching its own help text and `make app`'s existing scoping.
- **The formula started in a separate tap repo and moved into this one.** The first pass reasoned
  that the formula belongs in the tap, since a copy here would drift. Then `axklim/mbright` turned
  out to already solve this the other way: `Formula/` in the project repo, tapped by URL. One copy,
  no second repo, no drift either — so the tap repo was dropped and untapped.
- **`brew trust` was the thing we would have shipped wrong.** Homebrew 6 refuses formulae from
  untrusted third-party taps, so the install instructions need
  `brew trust --formula axklim/mynah/mynah` between the tap and the install. `mbright`'s README has
  it; ours would not have.
- **Auto-tap is the price of repo-as-tap.** Homebrew only auto-taps repos named `homebrew-<name>`,
  so `brew install axklim/mynah/mynah` fails until the two-argument `brew tap … <URL>` has been run.
  Verified both ways.
- The formula's `sha256` was a loud placeholder until `v0.1.0` was tagged; the tag landed the same
  day and it is now filled in. `brew install --HEAD` ignores it and works without any tag.

## Next step

The CLI is done: `v0.1.0` is tagged, `Formula/mynah.rb` is in the repo with the real checksum, and
installing through it was verified end-to-end.

Either close out **app distribution** — [[0010-homebrew-formula-cli-only]] lists three routes,
the most promising being a formula that installs a *prebuilt* bundle, since formula downloads are not
quarantined the way cask downloads are — or move to [[Roadmap|Phase 3]]'s polish loop. The three
translator follow-ups in [[inbox]] are still open, including `⌘C` not copying, which is shipped
behaviour.
