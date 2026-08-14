# 0010 — Homebrew ships the CLI as a from-source formula; the app waits

> **Superseded by [[0011-homebrew-tap-prebuilt]] (2026-08-14).** The tap moved to
> `axklim/homebrew-tap` and the formula now installs both products prebuilt. What survives is the
> measurement in the 2026-08-11 update below — formula downloads are not quarantined — which is
> what made shipping the app possible.

- **Status:** superseded by [[0011-homebrew-tap-prebuilt]]
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

The formula lives **in this repository** at `Formula/mynah.rb` — the repo *is* the tap, matching the
convention already in use at `axklim/mbright`. This replaces an earlier plan for a separate
`axklim/homebrew-tap` repo: one copy of the formula, no drift, no second repo to own.

The cost is that Homebrew cannot auto-tap, because auto-tap only resolves repos named
`homebrew-<name>`. Users need the two-argument `brew tap` with an explicit URL, and — on Homebrew 6 —
a `brew trust` step for any third-party tap:

```sh
brew tap axklim/mynah https://github.com/axklim/mynah
brew trust --formula axklim/mynah/mynah
brew install axklim/mynah/mynah
```

**Releasing.** Homebrew pins a release to a tag's tarball and that tarball's checksum, so a release is
a tag followed by a formula bump — the checksum cannot exist before the tag does. The version itself
has **one** home, `MynahVersion.swift`; `make app` generates `Info.plist` from `Info.plist.in` with it
substituted in, so the binary and the bundle cannot disagree.

**This is now automated** — run the **Release** workflow (`.github/workflows/release.yml`) from the
Actions tab with a version like `0.2.0` and it performs every step below, refusing to reuse an
existing tag and verifying a clean `brew install` from the published tag before it publishes the
release. The manual sequence is kept here because it is what the workflow does, and it is the
fallback when the workflow is unavailable:

1. Bump `MynahVersion.current` in `cli/Sources/MynahCore/MynahVersion.swift`. Commit to `main`.
2. `git tag -a v0.2.0 -m "mynah 0.2.0" && git push origin v0.2.0`
3. `curl -sL https://github.com/axklim/mynah/archive/refs/tags/v0.2.0.tar.gz | shasum -a 256`
4. Update `url` and `sha256` in `Formula/mynah.rb` and commit to `main`.
5. Verify: `brew uninstall mynah; brew install --build-from-source axklim/mynah/mynah`,
   `brew test mynah`, `brew audit --strict --formula axklim/mynah/mynah`, then a real
   `mynah check` — expect a verdict, not an error.

The formula's `test` block asserts `mynah --version` equals the version Homebrew derived from the
tarball URL. That is deliberate: it is the one release mistake the formula could not otherwise
see — a tag cut without step 1, leaving the binary reporting the previous version. `brew test` fails
instead of shipping it. `make version` prints the current value without grepping for it.

Because the formula lives in the repo it releases, step 4 always commits *after* the tag, so the
formula inside any release tarball is one commit stale. Harmless — Homebrew reads the default branch,
not the tarball's copy.

## Consequences

- `brew install axklim/mynah/mynah` gives the CLI on any Mac with the Command Line Tools. No Xcode, no
  API key — but it does need an authenticated `claude`, which the caveats state.
- **The menu-bar app — the daily driver — is still not distributed.** `make app` from a clone remains
  the only way to get it. This is the real cost of the decision and it is not small.
- Every release edits two lines in `Formula/mynah.rb` (`url`, `sha256`). `brew install --HEAD` needs
  neither and works straight from `main`.
- Tagging pushes to `axklim/mynah`, which needs the **personal** account — a work-authed session can
  push to the fork and open a PR, but not tag the release.

## Update (2026-08-11) — the prebuilt route is verified, and the cask route is closing

**Route 1 works. Measured, not assumed.** A throwaway formula that installed a zipped, ad-hoc-signed
`Mynah.app` from a local URL produced an installed bundle with **zero** `com.apple.quarantine`
attributes, and it **launched via `open`** (confirmed by its running pid out of the Cellar). Formula
downloads are not quarantined the way cask downloads are — checked independently against bottled
formulae already on this machine, whose binaries also carry no quarantine attribute.

Note `spctl -a --type execute` still reports **rejected** for the bundle, and that is not a
contradiction: `spctl` is the *assessment* API, which gates quarantined files. With no quarantine
attribute there is no assessment at launch. Do not "fix" this by reaching for notarization on the
strength of an `spctl` result alone.

**Route 2 is closing.** Homebrew is ending support for casks that fail Gatekeeper checks on
**1 September 2026** and deprecating `--no-quarantine` ([Homebrew/brew#20755]). For an un-notarized
bundle the cask route is not merely awkward, it is about to be unavailable — so the choice is
effectively route 1 or paying for a Developer ID.

So: **releases now carry `mynah-app-<version>.zip`**, built by CI on a macOS runner — which has Xcode
preinstalled, and is therefore the natural home for the one build step users cannot perform
([[preview-macro-needs-xcode]]). Shipping it *through a formula* is the remaining step, and it is now
a known-good path rather than a guess. The bundle is arm64-only; a universal build would want
`--arch arm64 --arch x86_64`.

Route 3 (a second formula with `depends_on xcode: :build`) is now clearly the worst option and can be
dropped.

[Homebrew/brew#20755]: https://github.com/Homebrew/brew/issues/20755

## Related

[[preview-macro-needs-xcode]] · [[Roadmap]] · [[Home]]
