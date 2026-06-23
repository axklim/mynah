# 0004 — Incremental development, foundation first

- **Status:** accepted
- **Date:** 2026-06-23

## Context

The developer explicitly wants to avoid designing the whole architecture or every edge case up
front. Instead: focus on one small part per session, solve it, verify it, then move on.

## Decision

Work **incrementally**, one small **verifiable** slice per session. The **first** slice is the
**foundation only** — context docs, the vault, the roadmap, and decision records. No app code
this session.

## Why

- Reduces wasted work from premature design.
- Every step ends in something demonstrably working, which keeps momentum and confidence.

## Consequences

- The [[Roadmap]] is a sequence of small slices, each with its own verify step.
- The CLI polish prototype (Phase 1) and the GUI (Phase 2+) are explicitly *not* in this first
  increment.

## Related

[[Roadmap]] · [[0005-obsidian-vault-as-source-of-truth]]
