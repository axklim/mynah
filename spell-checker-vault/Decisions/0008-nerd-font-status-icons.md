# 0008 — Status-item icons are Nerd Font glyphs, not emoji

- **Status:** accepted
- **Date:** 2026-08-04
- **Relates to:** [[0002-invocation-menubar-hotkey]] · [[0003-build-toolchain-xcode-later]] ·
  [[ad-hoc-translator]]

## Context

[[phase2-menubar-evaluator]] shipped the menu-bar icon as **emoji** set on the status-item button
title (⚪ ⏳ 🟢 🟡 🔴 📋 ⚠️) — the fastest thing that worked, with "upgrade to tinted SF Symbols
later" noted as the polish path. In use, the emoji look dated next to the rest of the developer's
setup, which is Nerd Font throughout (Ghostty is `font-family = "JetBrainsMono Nerd Font"`, tmux
and the shell prompt use the same glyph set).

Two candidates for the replacement: **SF Symbols** (ship with macOS, built for the menu bar,
nothing to install) or **Nerd Font glyphs** (visual consistency with the terminal and editor, but
they depend on a font being present).

## Decision

Use **Nerd Font glyphs** from **`JetBrainsMonoNF-Regular`** — the proportional variant, at the
PostScript name. Rendered as an `NSAttributedString` on the status-item button title, tinted via
`.foregroundColor`. The full state → codepoint table lives in [[ad-hoc-translator]].

Chosen over SF Symbols for one reason, and it is a real one: the menu bar should match the terminal
and editor the developer looks at all day. SF Symbols would be the safer engineering choice; visual
coherence won.

Three constraints come with it:

1. **`SpellCheckerCore` stays AppKit-free.** `IconState` exposes `glyph: String` plus an
   `IconTint` enum; `StatusItemController` (Bar target) maps tint → `NSColor`. Switching fonts, or
   moving to SF Symbols after all, is one file.
2. **Emoji fallback when the font is missing.** If `NSFont(name:)` returns nil, fall back to the
   current emoji titles. Otherwise a machine without the font shows an empty box where the app's
   only UI is. `Verdict.display` (terminal output) keeps its emoji permanently.
3. **Glyphs are `\u{f111}` escapes in source, never pasted characters** — private-use codepoints
   corrupt when retyped out of a rendered terminal.

## Consequences

- **A font dependency for distribution.** The app cask in [[Roadmap|Phase 2.2]] should declare
  `depends_on cask: "font-jetbrains-mono-nerd-font"`, or bundle `SymbolsNerdFont` into
  `Contents/Resources` and register it at launch with `CTFontManagerRegisterFontsForURL` (that font
  is not currently installed on this machine, so that path needs the file fetched). The exact cask
  DSL must be confirmed against Homebrew's docs at that point. A plain **formula** cannot depend on
  a cask, so the CLI stays font-free — it prints emoji anyway.
- **Codepoint identity must be verified by eye, not by name** — see
  [[nerd-font-codepoint-identity]]. A unit test asserts the font covers every codepoint
  `IconState` declares, skipping when the font is absent.
- Vertical centring needs a `.baselineOffset` nudge tuned against the real menu bar; unlike SF
  Symbols, Nerd Font metrics are built for a terminal cell.

## Related

[[ad-hoc-translator]] · [[phase2-menubar-evaluator]] · [[Roadmap]] · [[Home]]
