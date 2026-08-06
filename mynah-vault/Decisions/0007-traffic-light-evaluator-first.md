# 0007 — First prototype is a traffic-light evaluator (not a rewriter)

- **Status:** accepted
- **Date:** 2026-06-24
- **Relates to:** [[0001-llm-provider-claude]] · [[0006-polish-backend-claude-cli]]

## Context

Phase 1 first built a CLI that **rewrote** the message (the polish loop, pillar 1). The
developer is more interested, to start, in **evaluating** their own writing — knowing whether a
message reads clearly — than in a black-box rewrite they copy without learning anything.

## Decision

The first CLI prototype **evaluates** the text and returns **one traffic-light verdict**
(🔴 / 🟡 / 🟢) and nothing else — no rewrite, no explanation. Criteria: [[traffic-light-eval]].

- **red is comprehension-only.** The deciding axis is whether a reader will understand the
  intended meaning. Grammar/spelling mistakes — however many — stay **yellow** as long as the
  meaning is clear; **red** is reserved for genuinely unclear / ambiguous / double-meaning text.
- **Model: Sonnet** (`claude -p --model sonnet`). Evaluation is the analysis task
  [[0001-llm-provider-claude]] earmarked for a stronger model; Haiku under-detected ambiguity
  ([[haiku-misses-ambiguity]]).

## Why

- Matches the developer's actual need ("is this clear?") and the feedback & learning pillar
  ([[feedback-system]]) better than a one-shot rewrite.
- One signal is the smallest useful output and maps onto the spec's "use my original / skip
  correction" path: 🟢 send as is, 🔴 fix first.

## Consequences

- The polish/rewrite loop (pillar 1) is deferred to the GUI ([[Roadmap|Phase 3]]). The
  `claude -p` + provider-abstraction work from [[0006-polish-backend-claude-cli]] carries over —
  the protocol is now `TextEvaluator` instead of `PolishProvider`.
- Sonnet is slower than Haiku — acceptable for an occasional gut-check.
- Verdict reliability is sensitive to prompt calibration; the comprehension-only rule was added
  after Sonnet initially over-flagged an error-heavy-but-clear message as red
  ([[haiku-misses-ambiguity]]).

## Related

[[traffic-light-eval]] · [[Roadmap]] · [[Spec]]
