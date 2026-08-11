# 0009 — Rename the application to Mynah

- **Status:** accepted
- **Date:** 2026-08-06

## Context

The project started under the working name `spell-checker` — flagged in [[open-questions]] as
temporary, since the app is really a "message polisher + English coach." When the repo went
public (Phase 2.1) it was published as **github.com/axklim/mynah**, leaving the repo name and
the app/CLI names out of sync — awkward right before the Homebrew phase, where the formula
name becomes user-facing and hard to change.

## Decision

Rename everything to **Mynah** (a mynah is a bird famous for mimicking human speech — fitting
for an app that helps you sound natural):

- CLI binary `spell-checker` → **`mynah`**; menu-bar binary `spell-checker-bar` → **`mynah-bar`**
- App bundle `SpellChecker.app` → **`Mynah.app`**; bundle id `io.klimov.spellchecker` →
  **`io.klimov.mynah`**
- Modules `SpellCheckerCore/UI/Bar` → **`MynahCore`/`MynahUI`/`MynahBar`**
- Vault folder `spell-checker-vault/` → **`mynah-vault/`**

Historical records (`Sessions/`, `docs/superpowers/plans/`) keep the old names — they describe
what was true at the time.

## Consequences

- The new bundle id + fresh ad-hoc signature make macOS treat the app as brand new: the one-time
  TCC prompt ([[gui-claude-subprocess-tcc-prompt]]) reappears once, and any UserDefaults stored
  under the old id (shortcuts, migration flags — [[keyboardshortcuts-persists-its-default]]) are
  abandoned, not migrated. Defaults match the shipped shortcuts, so nothing user-visible changes.
- The old `spell-checker` binary in `~/.local/bin` and the old
  `Application Support/SpellChecker/` scratch dir linger until removed by hand.
- `mynah` has no hyphen, so the product/target name split in `cli/Package.swift` is now only
  lowercase-binary vs. CamelCase-module convention (plus the still-hyphenated `mynah-bar`).

## Related

[[Home]] · [[open-questions]] · [[Roadmap]]
