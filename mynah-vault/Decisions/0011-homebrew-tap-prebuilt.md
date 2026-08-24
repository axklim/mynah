# 0011 — Homebrew ships both products prebuilt from `axklim/homebrew-tap`

- **Status:** accepted
- **Date:** 2026-08-14
- **Supersedes:** [[0010-homebrew-formula-cli-only]] (the repo-as-tap and CLI-only halves; its
  measurements still stand and are what made this possible)
- **Relates to:** [[preview-macro-needs-xcode]] · [[gui-claude-subprocess-tcc-prompt]] · [[Roadmap|Phase 2.2]]

## Context

[[0010-homebrew-formula-cli-only]] shipped the CLI from source out of a tap that was the app repo
itself. It worked, but it left the daily driver — the menu-bar app — undistributed, and it made
every install compile Swift inside Homebrew's sandbox (hence `--disable-sandbox` and a fake `HOME`).

Two facts reframe it:

1. **This is a personal fleet.** A few Apple-silicon Macs, all mine. Developer ID, notarization,
   universal binaries, and "would a stranger need Xcode?" are not constraints — they were the
   entire reason the app half was hard.
2. **The prebuilt route was already measured.** 0010's 2026-08-11 update installed an ad-hoc-signed
   `Mynah.app` through a formula and found **zero** `com.apple.quarantine` attributes; it launched.
   Re-confirmed here on 2026-08-14: the installed bundle carries only `com.apple.provenance`.

## Decision

**One formula, `axklim/homebrew-tap/Formula/mynah.rb`, installing two prebuilt artifacts.**

```
brew install axklim/tap/mynah
        ↓
  bin/mynah          ← the CLI
  prefix/Mynah.app   ← the menu-bar app, via `brew services start mynah`
```

Both come out of a single release asset, `mynah-<version>-arm64.zip`, built by CI on `macos-15`
(which has Xcode, the one thing a stock machine lacks — [[preview-macro-needs-xcode]]).

Consequences of "nothing is compiled by Homebrew":

- `--disable-sandbox` and `ENV["HOME"]` are gone. So is the `Homebrew → Makefile → SwiftPM` hop;
  the Makefile keeps its local-dev and CI roles only.
- No `brew install --HEAD`. Local development is `make app`, unchanged.
- `depends_on arch: :arm64` — an Intel Mac is refused outright rather than falling back to a
  source build. If that ever matters, `make app` gains `--arch arm64 --arch x86_64`.

**The tap moved out of the app repo.** `axklim/homebrew-tap` already existed for `aerotab`, and a
conventionally named tap auto-taps: `brew install axklim/tap/mynah` needs no `brew tap` with an
explicit URL and no separate `brew trust` step. The cost 0010 avoided — two repos, formula drift —
is bought back by the release workflow, which is the only thing that edits the formula.

**Zipping.** Two top-level entries (`mynah`, `Mynah.app`), not a wrapper directory. Homebrew strips
a *single* top-level directory when unpacking; with two entries it strips nothing, so both
`bin.install` and `prefix.install` find their artifact.

## Releasing

> **Amended by [[0013-version-lives-in-the-git-tag]] (2026-08-24).** Steps 2 and 4 below no longer
> happen: the version is not stored in the tree and nothing is pushed to `main`, because a ruleset
> now requires a pull request there. The formula is rendered from `packaging/mynah.rb.tmpl` rather
> than `sed`-patched in the tap, and its explicit `version` line is gone — `brew audit --strict`
> rejects it as redundant with the version it scans from the URL. The asset is renamed
> `mynah-arm64-<version>.zip` (version **last**), because a brew older than 2026-07-28 scans the
> filename rather than the tag and reads `mynah-<v>-arm64.zip` as version `64`. Steps 1, 3 and
> 5–8 otherwise stand.

Same workflow, reordered — the formula points at an asset, so the asset must exist first:

1. Validate the version, refuse an existing tag.
2. Bump `MynahVersion.current`, cross-check with `make version`.
3. `make test && make build && make app`.
4. Commit, tag, push.
5. Zip `mynah` + `Mynah.app` → `mynah-<v>-arm64.zip`.
6. `gh release create` with the asset.
7. Clone `axklim/homebrew-tap` with **`TAP_TOKEN`**, rewrite `url` / `version` / `sha256`, push.
8. `brew tap axklim/tap && brew install axklim/tap/mynah && brew test mynah && brew audit --strict`.

Step 7 needs a secret because `GITHUB_TOKEN` cannot reach another repository: a fine-grained PAT
with `contents: write` on `axklim/homebrew-tap`, stored in `axklim/mynah` as `TAP_TOKEN`.

Step 8 is now a true end-to-end check — it installs the published asset through the pushed formula,
which is exactly what a machine gets. (The old workflow's equivalent step was also honest, contrary
to a critique that read the tap as pointing at a branch instead of the pinned tarball; the formula
it installed already pinned the tag's tarball and checksum.)

The formula's `test` block still asserts `mynah --version == version`. That is the one release
mistake nothing else catches: an asset that is not the version the formula names. (It used to
catch a tag cut without step 2; [[0013-version-lives-in-the-git-tag]] made that mistake
unrepresentable.)

## Caveats carried into the formula

- An authenticated `claude` CLI is required; there is no API key ([[0006-polish-backend-claude-cli]]).
- Ad-hoc signing means the bundle's code hash changes on every upgrade, so macOS privacy grants go
  stale silently ([[gui-claude-subprocess-tcc-prompt]]) —
  `tccutil reset SystemPolicyDownloadsFolder io.klimov.mynah` is in the caveats. `aerotab` learned
  the same lesson the hard way.

## Interaction with the config file ([[0012-xdg-config-language-pair]])

`brew services start mynah` launches the bundle through **launchd**, which is exactly the case
[[xdg-config-invisible-to-the-app]] describes: no shell environment, so no `$XDG_CONFIG_HOME`. The
installed app therefore resolves the fallback, `~/.config/mynah/config.conf`, while the installed
CLI follows the variable when one is set. On this fleet both paths name the same file, so nothing
diverges today — but `~/.config/mynah/config.conf` is the path to quote to anyone installing via
brew, since it is the one that holds under launchd.

## Migration

Per machine, once:

```sh
brew uninstall mynah
brew untap axklim/mynah
brew install axklim/tap/mynah
```

The formula landed in the tap with placeholder `url`/`sha256`/`version` for **v0.3.0** — there is no
v0.2.1 asset in the new shape — so it goes live with the first release cut by the new workflow.

## Verified

Dry run on 2026-08-14 before any tag: built the zip locally, installed the formula through a
`file://` URL out of a throwaway tap. `brew install` linked both artifacts, `brew test` passed all
three assertions, `brew audit --strict` came back clean (after it asked for `version` before
`sha256` and `assert_path_exists` over `assert_predicate`), and the installed bundle carried no
quarantine attribute.

## Related

[[0010-homebrew-formula-cli-only]] · [[preview-macro-needs-xcode]] · [[Roadmap]] · [[Home]]
