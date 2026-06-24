# Design — the traffic-light evaluation

The first prototype **evaluates** a message and returns **one** verdict — 🔴 / 🟡 / 🟢 — and
nothing else. It does **not** rewrite the text (that's the separate polish loop, pillar 1, now
in [[Roadmap|Phase 3]]). See [[0007-traffic-light-evaluator-first]].

## The verdict (comprehension-first)

The deciding axis is **whether a reader will correctly understand the intended meaning**, not
how many mistakes there are.

- 🟢 **green** — clear, natural, no real issues; safe to send as is.
- 🟡 **yellow** — the meaning is clear, but the wording is awkward / non-native or has grammar or
  spelling mistakes worth fixing. **Any number of mistakes stays yellow** as long as the meaning
  is not in doubt.
- 🔴 **red** — a reader might misunderstand: genuinely unclear, ambiguous, a double meaning, or
  could be read the wrong way.

red vs. yellow is a **comprehension** line, not an error-count line.

## The prompt (keep in sync with `cli/Sources/SpellChecker/TextEvaluator.swift`)

```
You are evaluating a message written by a non-native English speaker who wants to know whether it is ready to send. Decide the verdict by whether a reader will correctly understand the intended meaning — not by how many mistakes there are. Reply with EXACTLY ONE word and nothing else:

- green — clear, natural, and free of real issues; safe to send as is.
- yellow — the meaning is clear, but the wording is awkward or non-native, or has grammar or spelling mistakes worth fixing. Any number of mistakes stays yellow as long as the meaning is not in doubt.
- red — a reader might misunderstand it: the meaning is genuinely unclear, ambiguous, has a double meaning, or could be read the wrong way.

Reply with only one word: red, yellow, or green. Do not explain.

Message:
```

The user's message is appended after `Message:`.

## Implementation notes

- **Model: Sonnet.** Analysis quality > latency; Haiku under-detected ambiguity
  ([[haiku-misses-ambiguity]]).
- **Backend:** `claude -p` behind the `TextEvaluator` protocol
  ([[0006-polish-backend-claude-cli]]).
- **Parsing is lenient:** scan the reply for the first standalone red/yellow/green token, so a
  stray emoji/word doesn't break it; error out if none is found.

## Verified behaviour (2026-06-24)

| message | verdict |
|---|---|
| "Thanks for the review. I've merged the branch and deployed to staging." | 🟢 green |
| "i has finished the task and it works good now please to review when you has time thanks" | 🟡 yellow |
| "Please send the file to Anna and her assistant when she is ready." | 🔴 red |

## Related

[[Spec]] · [[feedback-system]] · [[polish-prompt]] · [[0007-traffic-light-evaluator-first]]
