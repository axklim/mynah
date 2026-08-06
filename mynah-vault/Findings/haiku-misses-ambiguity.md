# Finding — Haiku under-detects ambiguity; Sonnet catches it

- **Date:** 2026-06-24
- **Context:** calibrating the traffic-light evaluator ([[traffic-light-eval]]).

## What happened

Test sentence with a genuine double meaning:

> "Please send the file to Anna and her assistant when she is ready."
> (Is "she" Anna or the assistant?)

- `claude -p --model haiku` → 🟡 yellow (**missed** the ambiguity).
- `claude -p --model sonnet` → 🔴 red (**caught** it).

Catching double meanings is a core reason this tool exists, so we defaulted the evaluator to
**Sonnet** ([[0007-traffic-light-evaluator-first]]).

## Follow-on: Sonnet's initial over-correction

Sonnet then rated an **error-heavy but perfectly clear** message
("i has finished the task and it works good ...") 🔴 red — keying on mistake *count* rather than
comprehension. Fixed by making the prompt **comprehension-only**: red only when the meaning is
at risk; any number of grammar mistakes stays yellow if the meaning is clear. After tuning:
clear → 🟢, error-heavy-but-clear → 🟡, ambiguous → 🔴.

## Takeaway

- Use **Sonnet** (not Haiku) for the evaluation / analysis path.
- Verdict quality is sensitive to prompt calibration — state the deciding axis (comprehension)
  explicitly, or the model anchors on surface error count.

## Related

[[0007-traffic-light-evaluator-first]] · [[0001-llm-provider-claude]] · [[traffic-light-eval]]
