# 0005 — Obsidian vault as the source of truth

- **Status:** accepted
- **Date:** 2026-06-23

## Context

The project needs a home for ideas, problems, edge cases, decisions, and findings — usable by
both the developer and the assistant across many sessions.

## Decision

Keep an **Obsidian vault at `spell-checker-vault/`** in the repo as the **single source of truth**. Both the
developer and the assistant use it as a shared "second brain." This overrides any default of
storing specs elsewhere (e.g. `docs/superpowers/specs/`).

## Why

- Markdown + wikilinks + the graph view make a connected, browsable knowledge base.
- Lives in the repo, versioned with the code, available offline.

## Consequences

- New decisions → `Decisions/`; ideas → [[inbox]]; problems → `Problems/`; findings →
  `Findings/`; session logs → `Sessions/`.
- `Home.md` is the hub; link liberally so the graph stays connected.
- `.obsidian/` per-machine workspace state is git-ignored; notes and graph are committed.

## Related

[[Home]] · [[Spec]]
