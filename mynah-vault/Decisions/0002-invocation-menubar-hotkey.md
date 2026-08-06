# 0002 — Invocation: menu bar app + global hotkey

- **Status:** accepted
- **Date:** 2026-06-23

## Context

How should the developer reach the app during daily work? Options: a menu bar app with a global
hotkey popup, a standalone Dock window app, or a hybrid.

## Decision

**Menu bar app + global hotkey.** The hotkey opens a lightweight popup for quick polishing. The
larger **feedback dashboard** opens as a separate window from the menu bar when wanted.

## Why

- Matches the core use case: "polish any message quickly, from anywhere," with minimal friction.
- Keeps the fast path (polish) and the reflective path (dashboard) visually separate.

## Consequences

- App is menu-bar-resident (no Dock icon by default; `LSUIElement`-style).
- Need a global hotkey mechanism. Plan: Carbon `RegisterEventHotKey`, which does **not** require
  Accessibility permission (unlike a `CGEventTap`). See [[toolchain-notes]].

## Related

[[Spec]] · [[Roadmap]] · [[0003-build-toolchain-xcode-later]]
