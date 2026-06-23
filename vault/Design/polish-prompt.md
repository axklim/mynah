# Design — the polish prompt

## The prompt (verbatim — do not paraphrase)

```
Fix the grammar and make the text sound more natural. Use simple technical English and a
warm, cozy tone. Provide only one revised version:
```

The user's message text is appended after this prompt.

## Intent behind each clause

- **"Fix the grammar"** — correctness first.
- **"make the text sound more natural"** — idiomatic, not stiff or literal.
- **"simple technical English"** — plain words, suitable for engineering/work chat; no flowery
  vocabulary.
- **"warm, cozy tone"** — friendly and approachable, not cold or terse.
- **"Provide only one revised version"** — exactly one output, no options, no commentary. This
  matters: the popup shows a single result to copy.

## Implementation notes (for Phase 1+)

- Send as the user/input content with the original message appended; keep the instruction stable
  and verbatim so behavior is predictable.
- Model: **Haiku** for the polish loop (fast, cheap). Confirm exact model ID in
  [[open-questions]].
- The response should be **only** the revised text — strip any accidental preamble before
  showing/copying.
- Later, the same original+revised pair feeds the [[feedback-system]] (mistake capture). The
  *categorization* of mistakes is a **separate** call using a stronger model — keep it out of
  the fast path so polishing stays snappy.

## Open tuning questions

- Should tone be configurable later (e.g. "formal" preset)? Parked in [[open-questions]].
- Do we ever want multiple variants? Current answer: no — spec says one version.

## Related

[[Spec]] · [[feedback-system]] · [[0001-llm-provider-claude]]
