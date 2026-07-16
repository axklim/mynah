# 0006 — Polish backend: `claude -p` now, provider abstraction for later

- **Status:** accepted
- **Date:** 2026-06-23
- **Amends:** [[0001-llm-provider-claude]]

## Context

[[0001-llm-provider-claude]] assumed a direct Anthropic API call with a personal API key
(env var for the CLI, Keychain for the GUI). In practice the developer is on a **company
Claude Code account** and does not have a separate Anthropic API key to issue for this pet
project. The available Claude path is the Claude Code CLI in print mode (`claude -p`).

Separately, the longer-term plan is to route through **litellm** so the backend can be
**Gemini** (or any provider litellm fronts) behind one uniform interface.

## Decision

1. **Phase 1 backend = `claude -p --model haiku`.** The CLI prototype shells out to the
   Claude Code CLI instead of calling the Messages API directly. No API key required — it
   reuses the existing Claude Code auth.
2. **Put the LLM call behind a `PolishProvider` abstraction** (one method: text → revised
   text). Today's implementation is `ClaudeCLIProvider`; a future `LiteLLMProvider`
   (Gemini, etc.) conforms to the same protocol. This walks back the "YAGNI on the
   abstraction" stance in [[0001-llm-provider-claude]] — the abstraction is now justified
   because we already know we'll swap backends.

## Why

- It's the only Claude option that works **today** with the company account (no key to obtain).
- Verified working: `claude -p --model haiku` + the verbatim [[polish-prompt]] returns one
  clean revised version, no preamble.
- The abstraction makes the eventual litellm/Gemini swap a localized change, not a rewrite.

## Consequences

- **Not the shipping architecture.** A distributed `.app` can't assume Claude Code is
  installed and logged in. The provider abstraction is what lets the production build move to
  litellm/Gemini (or a direct API) later.
- **Harness overhead.** Each `claude -p` call boots the full Claude Code agent (system prompt,
  tools, skills, MCP, hooks), so it's heavier/slower than a raw API call — acceptable for the
  prototype, a concern for the "daily, fast" polish loop long-term.
- The provider reads only **stdout**; stderr is discarded (it can carry unrelated hook noise
  from the user's global Claude Code config).
- Model is selected via the `claude --model` alias.
- **Update (2026-06-24):** the first prototype became a traffic-light **evaluator**, so the
  protocol is now `TextEvaluator` (was `PolishProvider`) and the default model is `sonnet` — see
  [[0007-traffic-light-evaluator-first]]. The `claude -p` backend mechanism is unchanged.

## Update (2026-06-25) — PATH resolution for GUI launch

A GUI `.app` launched from Finder does **not** inherit the interactive shell `PATH`, so
`claude` (typically in `~/.local/bin` or Homebrew) is invisible to the default
`/usr/bin:/bin:/usr/sbin:/sbin` search path and the shell-out fails silently.

**What shipped:** `ClaudeCLIEvaluator.resolveClaudeURL()` probes the known install locations
(`~/.local/bin/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`) and returns the
first executable it finds. If none match, it falls back to `/usr/bin/env claude`, which still
resolves correctly for terminal runs where `PATH` is inherited. See [[phase2-menubar-evaluator]]
for the full design note.

A login-shell probe (`/bin/zsh -lc 'command -v claude'`) was considered but not shipped; it
remains a possible future fallback for non-standard installs.

## Related

[[0001-llm-provider-claude]] · [[polish-prompt]] · [[Roadmap]] · [[Spec]]
