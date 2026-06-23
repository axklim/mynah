# Session 01 — Foundation (2026-06-23)

## Goal

Stand up the project foundation: project context + the Obsidian vault (second brain) + the
roadmap and decision records. No app code this session — keep it verifiable without Xcode.

## What we did

- Ran a short brainstorm and locked in four decisions:
  [[0001-llm-provider-claude]], [[0002-invocation-menubar-hotkey]],
  [[0003-build-toolchain-xcode-later]], [[0004-incremental-foundation-first]],
  plus [[0005-obsidian-vault-as-source-of-truth]].
- Wrote `CLAUDE.md`, `README.md`, `.gitignore` at the repo root.
- Built the vault: [[Home]] (hub), [[Spec]], [[Roadmap]], the five decision notes, design notes
  ([[polish-prompt]], [[feedback-system]], [[data-model]]), [[inbox]], [[open-questions]], and
  the [[toolchain-notes]] finding.

## Environment notes

macOS 26.4.1 / Apple Silicon, Swift 6.3.2 via Command Line Tools, **no Xcode yet**, Obsidian
installed. Details: [[toolchain-notes]].

## Verified

- Vault structure created; all notes non-empty.
- (To confirm) opens cleanly in Obsidian with wikilinks resolving.

## Next step

**Phase 1 — CLI polish prototype** (see [[Roadmap]]): a `swift` command-line program that reads
text, calls Claude with the [[polish-prompt]], and prints one revised version. First confirm the
exact Claude model ID and have an Anthropic API key ready (env var). This needs no Xcode.

## Open questions raised

See [[open-questions]] — app name, exact model IDs + cost, privacy messaging.
