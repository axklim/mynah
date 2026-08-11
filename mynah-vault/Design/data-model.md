# Design — data model (storage)

> Status: **early sketch**, not built yet (Phase 4+). On-device, single user. Exact storage tech
> (JSON file vs. SQLite vs. SwiftData) to be decided when we reach Phase 4 — start simple.

## Entities (conceptual)

### PolishEvent
One per polish that produced a correction.
- `id`
- `createdAt`
- `originalText`
- `revisedText`
- `accepted` — did the developer use the revision, or keep their original (the skip path)?
- `model` — which model produced the revision

### MistakeRecord
Zero or more per `PolishEvent`, produced by the categorization step.
- `id`, `polishEventId`
- `category` — controlled vocabulary (e.g. `article`, `agreement`, `word-choice`,
  `spelling`, `tone`, `punctuation`, …)
- `label` — short human-readable description
- `before` / `after` — the specific span as written vs. corrected

### TypoEntry (the personal dictionary)
Derived/aggregated from `spelling`-category records.
- `wrong` (normalized), `correct`
- `count`, `firstSeen`, `lastSeen`

## Aggregations (computed, not stored long-term)

- Category counts over a window → the **common-mistakes overview**.
- Top categories → **exercise** topic selection.
- Spelling records rolled up → the **typo dictionary**.

## Notes

- Keep raw text **on-device**; it's sensitive ([[open-questions]] — Privacy).
- Start with the simplest thing that works (likely a JSON store) and migrate to SQLite/SwiftData
  only if/when volume or query needs demand it. YAGNI.

## Related

[[feedback-system]] · [[Spec]]
