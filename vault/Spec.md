# Spec — living product spec

> Status: **draft, evolving**. This is the source of truth for *what* we're building. It will
> grow as increments land. See [[Roadmap]] for *when* and [[Home]] for navigation.

## Problem

The developer is a non-native English speaker. They aren't always sure their messages read
clearly, sound natural, or are free of double meanings and contradictions. The current fix is
manual and breaks flow: write → paste into ChatGPT with a fixed prompt → copy the result back.

## Goal

Take over that loop inside a fast, native macOS app — **and** turn the corrections into a
gentle, long-term learning system so the same mistakes stop recurring.

## Pillar 1 — Polish loop (daily, fast)

**Trigger:** a global hotkey from anywhere → a small popup window appears.

**Flow:**
1. The popup focuses an input field; the developer types or pastes a message.
2. *Polish* sends the text to Claude with the [[polish-prompt]] (Haiku for speed).
3. The popup shows **one** revised version.
4. The developer copies the result back (auto-copy on accept is a candidate behavior).
5. **Skip path:** an explicit "use my original / it's already fine" action that closes the loop
   without a correction. This is a first-class option, not an afterthought — sometimes the
   message is already good and the developer just wants to move on.

**Principles:** minimal friction, keyboard-first, no modal nagging, never block on the network
longer than necessary (show progress, allow cancel).

## Pillar 2 — Feedback & learning (periodic, reflective)

The key idea: **don't explain in the moment.** Corrections during the polish loop should not
interrupt with grammar lessons. Instead, the app silently records what changed and teaches
later, on demand.

**Captured per polish:** the original text, the revised text, and a categorization of the
mistakes (grammar topic, spelling/typo, word choice, tone, etc.). See [[feedback-system]] and
[[data-model]].

**Surfaced later (the dashboard, opened from the menu bar):**
- **Common-mistakes overview** — a short, ranked summary of recurring mistake types.
- **Grammar explanations & rules** — simple, friendly explanations tied to the topics that
  actually come up for *this* developer.
- **Exercises** — small drills generated for the most frequent mistake topics.
- **Personal typo dictionary** — frequent spelling/typing mistakes, tracked so they fade over
  time.

## Non-goals (for now)

- Not a general writing suite or document editor.
- Not multi-user / cloud-synced. Single user, on-device.
- Not real-time inline correction inside other apps (it's an explicit popup, by design).

## Constraints & qualities

- **Native & fast.** Swift/SwiftUI, menu bar resident, instant popup.
- **Private by default.** Message text is sensitive; store locally, be explicit that polish
  requests are sent to Anthropic. (See Privacy in [[open-questions]].)
- **Incremental.** Each capability ships as its own verifiable slice ([[Roadmap]]).
