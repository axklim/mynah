# 0010 — Homebrew ships the CLI as a from-source formula; the app waits

- **Status:** accepted (the app half is still open — see Open question below)
- **Date:** 2026-08-11
- **Relates to:** [[0003-build-toolchain-xcode-later]] · [[0008-nerd-font-status-icons]] ·
  [[preview-macro-needs-xcode]] · [[Roadmap|Phase 2.2]]

## Context

[[Roadmap|Phase 2.2]] asks for `brew install`, shipping `mynah` "and, if practical, the menu-bar
app". Two things decided the shape, and both were discovered rather than assumed.

**A cask is not practical yet.** A cask ships a prebuilt bundle, and `make app` only ad-hoc signs
(`codesign --sign -`). Homebrew marks cask downloads with `com.apple.quarantine`, so an unsigned,
un-notarized bundle is blocked by Gatekeeper on launch. A clean cask needs a paid Developer ID and
notarization, which the project does not have. Building from source avoids the whole problem:
locally compiled binaries carry no quarantine flag.

**The app cannot be built from source on a stock machine.** [[preview-macro-needs-xcode]]: the
`KeyboardShortcuts` dependency uses `#Preview`, whose macro plugin ships only inside Xcode. A
formula that built the app would make ~10 GB of Xcode a prerequisite for a menu-bar utility. The
CLI has no such problem — it compiles against the CLT SDK alone.

## Decision

One formula, `axklim/tap/mynah`, that **builds the `mynah` CLI from source** and installs nothing
else. It goes through the project's own `make install PREFIX=…` so there is a single definition of
what "installed" means. Font handling from [[0008-nerd-font-status-icons]] does not apply: the CLI
prints emoji, so there is no font dependency to declare (and a formula could not depend on a cask
anyway).

Two build-environment facts are encoded in the formula:

1. **`SWIFT_FLAGS=--disable-sandbox`.** A Homebrew build is already sandboxed, and SwiftPM starts a
   *nested* `sandbox-exec` to compile `Package.swift`. Nesting is refused
   (`sandbox_apply: Operation not permitted`), surfacing as "Invalid manifest". The `Makefile` gained
   a `SWIFT_FLAGS ?=` seam for this; local development keeps SwiftPM's sandbox on, since it is a
   real safety feature.
2. **`ENV["HOME"] = buildpath/"brew-home"`.** SwiftPM's caches live under the real `$HOME`, outside
   the sandbox, and it warns and disables user-level caching without a writable one.

The formula lives **only in the tap repo** (`axklim/homebrew-tap`), not in this repository. A second
copy here would drift, and the tap is what Homebrew actually reads. `RELEASING.md` in the tap holds
the tag-and-checksum procedure.

## Consequences

- `brew install axklim/tap/mynah` gives the CLI on any Mac with the Command Line Tools. No Xcode, no
  API key — but it does need an authenticated `claude`, which the caveats state.
- **The menu-bar app — the daily driver — is still not distributed.** `make app` from a clone remains
  the only way to get it. This is the real cost of the decision and it is not small.
- Every release edits two lines in the tap (`url`, `sha256`). `brew install --HEAD` needs neither and
  works straight from `main`.
- The tap must exist on GitHub under the **personal** account; it cannot be created from a work-authed
  session.

## Open question — how the app eventually ships

Deliberately left open. Three candidates, in rough order of preference:

1. **Formula installs a prebuilt app.** Formula downloads are *not* quarantined (unlike casks), so an
   ad-hoc-signed `Mynah.app` attached to a GitHub release could be installed by a formula and launch
   without Gatekeeper friction, with no Xcode and no notarization. Needs verifying rather than
   assuming, and the build would want `--arch arm64 --arch x86_64` to be universal.
2. **Cask + notarization.** The correct long-term answer; costs a Developer ID subscription.
3. **Second formula `mynah-bar` with `depends_on xcode: :build`.** Honest, works today, but asks
   users for Xcode.

## Related

[[preview-macro-needs-xcode]] · [[Roadmap]] · [[Home]]
