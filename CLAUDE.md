# CLAUDE.md — Project context

> **Read `vault/Home.md` first.** The Obsidian vault at [`vault/`](vault/Home.md) is the
> single source of truth for this project — ideas, decisions, problems, designs, and findings
> all live there. This file is just the quick orientation.

## What this is

A **native macOS app** that helps a non-native English speaker send clear, natural messages.

The developer writes messages all day (chat, email, PRs) and isn't always sure they read
clearly, sound natural, or are free of double meanings. Today the workflow is manual: write →
paste into ChatGPT with a fixed prompt → copy the result back. This app takes over that loop
**and** quietly learns from the mistakes so the developer improves over time.

## The two pillars

1. **Polish loop (daily, fast).** A global hotkey opens a lightweight popup. Type or paste a
   message, hit *Polish*, get **one** revised version from Claude, copy it back. There is always
   an explicit **"use my original / skip correction"** path for when the message is already good.

2. **Feedback & learning (periodic, reflective).** The app records the difference between what
   the developer wrote and the polished text and categorizes the mistakes — but it **does not
   explain in the moment**. Later, on demand, it surfaces:
   - a short overview of the most common mistakes,
   - simple grammar explanations & rules,
   - small exercises for the most frequent mistake topics,
   - a personal dictionary of frequent typing/spelling mistakes.

## Tech decisions (locked in — see `vault/Decisions/`)

| Area            | Decision                                                                 |
|-----------------|--------------------------------------------------------------------------|
| LLM             | Anthropic Claude — Haiku for polishing, a stronger model for analysis    |
| Invocation      | Menu bar app + global hotkey → popup; larger window for the dashboard    |
| Language / UI   | Swift 6 / SwiftUI + AppKit                                               |
| Build toolchain | Xcode (to be installed later); until then, only `swift` CLT work         |
| Secrets         | API key in macOS Keychain (GUI) / env var (CLI prototype)                |
| Storage         | Local, on-device (message text is sensitive — see Privacy in vault)      |

## Development philosophy

- **Incremental.** One small, self-contained slice per session.
- **Verify before moving on.** Every slice must be demonstrably working before the next starts.
- **Vault as the second brain.** Capture ideas, decisions, problems, and findings in `vault/`
  as we go. When something non-obvious is decided or discovered, write it down there.

See `vault/Roadmap.md` for the phased plan and current status.

## The polish prompt (verbatim — do not paraphrase)

```
Fix the grammar and make the text sound more natural. Use simple technical English and a
warm, cozy tone. Provide only one revised version:
```
