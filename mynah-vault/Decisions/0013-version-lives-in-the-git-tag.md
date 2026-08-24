# 0013 — The version lives in the git tag, and the release never pushes to `main`

- **Status:** accepted
- **Date:** 2026-08-24
- **Amends:** [[0011-homebrew-tap-prebuilt]] (its "Releasing" steps 2 and 4 — the rest stands)
- **Relates to:** [[0010-homebrew-formula-cli-only]] · [[Roadmap|Phase 2.2]]

## Context

The v0.4.0 release failed. Not in the build, not in the formula — in `git push origin main`:

```
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
```

`axklim/mynah` grew a ruleset on `main`: pull request required, one approving review, code-owner
review, linear history, rebase-only merges. That ruleset is right. The release process was written
before it existed, and step 2 of [[0011-homebrew-tap-prebuilt]] — "bump `MynahVersion.current`" —
made a commit that step 4 then had to push to `main`. A protected branch and an automated
version-bump commit cannot both be true.

Three ways out:

1. **Grant the workflow a bypass.** Keeps the bump, defeats the ruleset for the one actor most
   worth constraining, and leaves `main` mutable by CI forever.
2. **Open a PR for the bump.** A release would then block on a human approving a one-line commit
   the machine wrote — and the tag could only be cut after the merge, in a second run.
3. **Stop storing the version in the tree.** Then there is nothing to commit, and the only thing
   pushed is a tag — which is not subject to a *branch* rule at all.

`axklim/flyspace` had already taken route 3 and had a release process built around it. This
decision ports it, rather than inventing a second answer to the same question.

## Decision

**The version's only home is the git tag.** `MynahVersion.swift` is now a *generated* file:

```
git tag v0.4.0                    ← the version
        ↓
scripts/version.sh                ← MYNAH_VERSION → .git_archival.txt → "0.0.0-dev"
        ↓
scripts/stamp-version.sh          → cli/Sources/MynahCore/MynahVersion.swift
make app                          → Mynah.app/Contents/Info.plist
```

- `.git_archival.txt` + `.gitattributes export-subst` — `git archive`, which is what GitHub runs
  to build a tag tarball, expands `$Format:%(describe:tags=true,match=v[0-9]*)$` to the tag name.
  That is how a tarball knows its own version with the version nowhere in the tree.
- A plain checkout leaves that placeholder literal, so it builds as **`0.0.0-dev`** — the value
  committed in `MynahVersion.swift`, so a bare `swift build` still works.
- **`MYNAH_VERSION`** overrides both. That is what lets the release workflow build, stamp and
  *verify* the artifacts before the tag they will be derived from exists.
- `stamp-version.sh` rewrites the Swift file only when its content actually changes; an
  unconditional write would recompile `MynahCore` on every build for nothing.

**The formula is rendered here, not patched there.** `packaging/mynah.rb.tmpl` +
`scripts/render-formula.sh` (`make formula VERSION=… SHA256=…`) replace the three `sed -i` lines
the old workflow ran inside a tap checkout. The formula is now reviewable in the repository it
describes, CI lints it on every PR, and the renderer refuses a malformed version, a malformed
checksum, or a placeholder that survived substitution.

## The release, reordered

Everything that can fail is made to fail *before* anything is public:

1. Validate the version; refuse an existing tag (`git rev-parse -q --verify refs/tags/vX`).
2. `make test && make build && make app` with `MYNAH_VERSION` set; assert the CLI **and** the
   bundle both report it.
3. Zip `mynah` + `Mynah.app`; take the sha256 of the asset we just built.
4. Render the formula against that real checksum; `brew style`, `brew audit --strict`, and ask
   `brew info --json` what version it *resolved* — the one thing style and audit cannot catch.
5. Prove `TAP_TOKEN` can push, with `git push --dry-run`. A read proves nothing: the tap is
   public, so an expired token clones it happily and only fails at `git-receive-pack`.

— nothing above this line published anything —

6. Tag and push the tag. No commit. No push to `main`.
7. `gh release create` with the asset.
8. Render the formula into `axklim/homebrew-tap` and push it.
9. In a separate job with `permissions: {}`: `brew install axklim/tap/mynah && brew test mynah &&
   brew audit --strict`, and assert `mynah --version`.

Two smaller fixes came with it, both borrowed from flyspace:

- **`concurrency: group: release`** — two dispatches must not race the tag push and the tap commit.
- **`env: VERSION: ${{ inputs.version }}`, read back as `"$VERSION"`.** Splicing `${{ }}` into
  shell text lets GitHub substitute before bash parses, so a version containing a quote breaks out
  and runs arbitrary commands with `contents: write` and `TAP_TOKEN` in scope.

## Found while porting

`brew audit --strict` now **rejects** the formula's explicit `version "X.Y.Z"` line:

```
* Stable: `version 0.4.0` is redundant with version scanned from URL
```

Homebrew's scanner reads `0.4.0` out of `…/download/v0.4.0/mynah-0.4.0-arm64.zip` on its own.
[[0011-homebrew-tap-prebuilt]] added that line believing an asset URL could not be scanned; it can.
The line is gone from the template, and step 4's `brew info --json` check is what keeps the
scanner honest. This would have failed the *last* step of the next release either way — after the
tag and the release were already public.

## Consequences

- A version bump is no longer a code change. `MynahVersion.swift` should never be edited by hand
  again, and its committed value stays `0.0.0-dev`.
- Local `make app` builds a bundle that says `0.0.0-dev`. Honest: it is not a release.
- A release build leaves `MynahVersion.swift` dirty in the runner's checkout. Nothing commits it,
  so nothing cares.
- `main` stays protected, with no bypass actor and no exception for CI.
