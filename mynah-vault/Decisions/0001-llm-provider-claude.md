# 0001 — LLM provider: Anthropic Claude

- **Status:** accepted
- **Date:** 2026-06-23

## Context

The polish loop and (later) the mistake analysis both need an LLM. The developer currently uses
ChatGPT manually. Options considered: Anthropic Claude, OpenAI, a local model (Ollama), or a
provider-agnostic abstraction.

## Decision

Use **Anthropic Claude**. Plan: **Haiku** for fast, cheap polishing; a **stronger model**
(e.g. Sonnet) for the periodic mistake analysis where quality matters more than latency.

## Why

- Strong at natural, warm tone — exactly what the polish prompt asks for.
- Single provider keeps the first increments simple (YAGNI on the abstraction).

## Consequences

- Requires an Anthropic API key. Stored in Keychain for the GUI; an env var for the CLI
  prototype. Never commit keys.
- Message text is sent to Anthropic — note the privacy implication ([[open-questions]]).
- Exact model IDs and rough per-message cost to be confirmed before Phase 1 ([[open-questions]]).

## Related

[[Spec]] · [[polish-prompt]] · [[Roadmap]]
