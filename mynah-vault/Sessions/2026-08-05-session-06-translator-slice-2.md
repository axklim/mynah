# Session 06 — Translator slice 2: `spell-checker translate` (2026-08-05)

## Goal

Ship slice 2 of the [[ad-hoc-translator]] ([[Roadmap|Phase 2.3]]): English → Russian translation in
`SpellCheckerCore`, exposed as `spell-checker translate`, so the prompts could be tuned in a
terminal before any GUI exists. Slice 1 landed on `main` as `e141393` the day before.

## What we did

Six tasks on branch `translator-slice-2`, each individually reviewed.

- **`ClaudeCLI` extracted.** The `claude -p` plumbing was private to `ClaudeCLIEvaluator`; the
  translator needed the same thing. It now lives once, so the Finder-`PATH` resolution and the
  empty app-private working directory ([[gui-claude-subprocess-tcc-prompt]]) have a single home.
- **`TranslationMode.forInput`** splits 1–2 words (a vocabulary lookup) from 3+ (prose).
- **Types, prompts and a lenient parser.** `WordMeaning`, `TranslationResult`, a `TextTranslator`
  protocol as the second backend-swap point ([[0006-polish-backend-claude-cli]]), and
  `parseWordResult`, which slices from the first `{` to the last `}` because `claude -p` fences
  JSON however firmly the prompt forbids it. Over three meanings are clamped and **force**
  `hasMore` — dropping one is itself a reason to say more exist.
- **`spell-checker translate`**, with `TranslationResult.terminalText(source:)` in Core rather than
  the CLI target, because an executable target cannot be imported by the test bundle.
- **Docs** across five files.

## Verified

- 41 tests, 0 failures (23 inherited + 6 mode + 9 parse + 3 renderer). `make build` clean.
- **The prompts work, judged by reading real output** — the whole reason this slice preceded the
  GUI. `translate "commit"` returned three genuinely distinct senses (wrongdoing / promise /
  version control), explanations of 12–13 words in plain English, and examples each incompatible
  with the other two rows. A sentence returned one bare Russian line, no quotes or preamble. No
  fixture could have established any of that.
- Task 1's refactor was proven by the suite staying at **exactly** 23 tests, plus one real
  `check` call still returning 🟢.

## Two things worth remembering

**Cancellation groundwork that cannot yet be used.** `ClaudeCLI.run` gained an
`onStart: ((Process) -> Void)?` hook for slice 3, because dismissing the panel must kill an
in-flight call and Swift `Task` cancellation cannot — the pipe read blocks in a way that ignores
it. The final review traced it and found the hook is **unreachable from outside Core** for two
independent reasons: `ClaudeCLI` is `internal`, *and* neither public entry point accepts or
forwards it. Slice 3 must thread it through `ClaudeCLITranslator.translate`, and probably through
the `TextTranslator` protocol too. The hook sits in the right place; it is necessary, not
sufficient. **Do not plan slice 3 as though cancellation is solved.**

**A `$` prompt is a claim that a session happened — and we broke that twice.** `cli/README.md`
first shipped a `$ spell-checker translate commit` block whose Russian was invented during
brainstorming, before any code could run. Replacing it, the replacement was then trimmed "so the
lines fit", which the final review caught by diffing the docs against the real transcript. The
docs now carry the exact output, long lines and all. The rule that came out of it: a `$` block is
verbatim or it loses the `$`.

## Notes

- **Every finding this slice originated in plan text, not in implementation.** A Foundation import
  that could not work, a dropped comment about macOS privacy prompts being only partly mitigated,
  a duplicated input guard, an invented transcript, and a subject–verb slip — in the docs for a
  tool whose purpose is helping a non-native speaker write clear English. The implementers copied
  faithfully every time; the review layer earned its cost. The cheapest available improvement is
  more careful plans, not more review passes.
- The input guard is shared through a `requireInput` helper in `main.swift` rather than duplicated
  per subcommand, after review flagged two copies of the character-limit message. Slice 1 had
  already shipped that exact shape once (a duplicated font-name literal behind a "change both"
  comment that nothing enforced).
- **All 13 commits carry the required `Co-Authored-By` trailer**, versus 10 of 21 missing on slice
  1's branch — the fix-forward held.
- The final whole-branch review ran on Sonnet, not Opus: Opus returned 529 Overloaded twice.
- **Known blind spot:** `translate`'s mode→prompt dispatch and all of `main.swift`'s wiring have
  zero automated coverage. A regression swapping the `.word`/`.text` branches, swapping which type
  a CLI case builds, or flipping an exit code would compile clean and leave 41/41 green. The same
  has been true of `check` since Phase 1. "41 tests" covers pure logic units, not wiring.

## Next step

**Slice 3** — the floating `NSPanel` on Hyper+⇧C: `NSHostingView` content, Esc and focus-loss
dismissal, the 文A `translating` icon state, and cancellation (see the carry-forward above).
Note `U+F05CA` is above U+FFFF, exactly the class of codepoint
[[nerd-font-codepoint-identity]] says must be coverage-checked — and `IconState.allStates` is
hand-maintained with a hardcoded count in its test, so adding the case without extending the array
would leave the font-coverage test silently skipping the new glyph.
