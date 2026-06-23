# Design — feedback & learning system

> Status: **early design**, not built yet (Phases 4–7 in [[Roadmap]]). This note captures the
> shape so future sessions share a mental model. Details will firm up when we get there.

## Core principle

**Teach later, not in the moment.** The polish loop must stay fast and non-judgmental. Mistakes
are recorded silently and surfaced only when the developer opens the dashboard to reflect.

## Pipeline (conceptual)

1. **Capture** — on each polish, store the `original` and `revised` text (+ timestamp). See
   [[data-model]].
2. **Categorize** — a separate, off-the-fast-path LLM call (stronger model) compares original
   vs. revised and emits structured mistake records: a category (e.g. *article use*,
   *subject–verb agreement*, *word choice*, *spelling/typo*, *tone*), a short human label, and
   the specific span/word involved.
3. **Aggregate** — count categories over time to find what recurs most for *this* developer.
4. **Surface** — the four learning outputs below, on demand.

## The four learning outputs (from the spec)

1. **Common-mistakes overview** — a short ranked list of the developer's most frequent mistake
   types, with counts and trend (improving / recurring).
2. **Grammar explanations & rules** — simple, friendly explanations tied to the categories that
   actually show up. Likely a small curated rule library keyed by category, optionally enriched
   by the LLM with examples drawn from the developer's own corrections.
3. **Exercises** — small generated drills targeting the top recurring topics. A few items at a
   time; track whether the developer gets them right.
4. **Personal typo dictionary** — frequent spelling/typing mistakes (the *spelling* subset of
   categories), with the correct form, surfaced so they fade over time.

## Open questions

- How aggressively to categorize — every polish, or batched periodically to save cost/latency?
- Rule library: hand-curated vs. LLM-generated vs. hybrid?
- How to measure "improving" (decay window, streaks)?

Parked in [[open-questions]].

## Related

[[Spec]] · [[data-model]] · [[polish-prompt]] · [[Roadmap]]
