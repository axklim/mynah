# 0012 — Language pair becomes an XDG config file, default flips to English → German

- **Status:** accepted
- **Date:** 2026-08-14
- **Relates to:** [[configurable-language-pair]] · [[ad-hoc-translator]] ·
  [[0006-polish-backend-claude-cli]]

## Context

[[ad-hoc-translator]] shipped the translator hard-wired **English → Russian** — the direction lived
inside two prompt string constants in `TextTranslator.swift`, chosen because the developer who built
it is a Russian speaker. The developer has since moved to Germany and wants **English → German**
day to day, with Russian still reachable for the odd message. Hard-coding a second pair is the wrong
answer to that: the direction was never a decision worth freezing in source, it was just the first
value that happened to be true.

## Decision

The language pair becomes a setting, not a constant:

- **Exactly one active pair, both sides configurable.** `source` and `target` are independent
  strings — no list of pairs, no `--to` flag, no second hotkey. Changing direction (or adding a
  third language) is a config edit, never a rebuild.
- **Read from an XDG file**, `key = value` with `#` comments, hand-parsed — no new package
  dependency for three keys. `$XDG_CONFIG_HOME/mynah/config.conf` when that variable is set to an
  absolute path, else `~/.config/mynah/config.conf`. A missing file means the defaults; a file that
  exists but cannot be read (permissions, non-UTF-8) is an error, not a silent fallback — the whole
  point of a small hand-edited file is that a typo should be loud.
- **Plain English language names** (`German`, `Brazilian Portuguese`), not ISO codes. The only
  consumer is a natural-language prompt, which already understands "German" — a code would need a
  translation table in Core before the prompt could say anything, and that table is one more thing
  to maintain and be missing an entry from.
- **Default is English → German**, model `sonnet`. The old English → Russian default is one config
  edit away, not lost.
- **Parsing is strict.** An unknown key, a duplicate key, an empty value, a language name over 40
  characters, or `source` equal to `target` (case-insensitively) is an error naming the file and
  line. There is no forward-compatibility argument for tolerating unknown keys here.
- **The pair enters through the translator's initialiser**, not the `TextTranslator` protocol.
  `ClaudeCLITranslator(languages:model:)` takes the resolved config; `TextTranslator` itself gained
  no new parameter. This was chosen over making the pair a per-call argument
  (`translate(_:to:)`) specifically to leave alone the one interface the project deliberately froze
  for a future litellm/HTTP backend swap ([[0006-polish-backend-claude-cli]]).
- **Word-mode explanations and examples follow the source language**, not a hard-coded English.
  The old prompt opened with "you are helping a Russian-speaking developer" — with the pair
  configurable, the reader's native language is no longer derivable from it, so that framing is
  gone and the three JSON fields are pinned to source/target roles instead.
- **`mynah config`** is a new subcommand: prints the resolved path (found or not) and the effective
  settings as a valid config file, so it doubles as both the "where is my config" answer and the
  init step (`mynah config > ~/.config/mynah/config.conf`).

Full design, including the file grammar, the rejected alternatives (a named-pairs list with a
submenu, config loading living inside the translator itself), and the test list, is in
[[configurable-language-pair]].

## Consequences

- **The project's first config file of any kind.** Every future "make X configurable" question
  now has a home and a precedent to match, rather than a fresh decision each time.
- **`mynah check` is unchanged and stays English-only.** It evaluates the English the developer is
  about to send — that's the app's actual purpose — so wiring `source` into it would be a
  different decision, not a detail of this one. It does not read the config file at all.
- **The CLI and the app can read `$XDG_CONFIG_HOME` differently.** A Finder- or
  `launchd`-launched `.app` inherits no shell environment, so a variable set in a shell rc is
  invisible to `Mynah.app` even though the `mynah` CLI in the same terminal sees it — see
  [[xdg-config-invisible-to-the-app]]. They agree whenever the variable is unset, which is the
  common case, so this is a documented edge rather than a day-to-day surprise.
- **A stale default is now just a config edit.** The open inbox item "try Haiku for the
  translator's text mode" becomes `model = haiku` in the file instead of a code change.

## Related

[[Home]] · [[configurable-language-pair]] · [[ad-hoc-translator]] ·
[[0006-polish-backend-claude-cli]] · [[xdg-config-invisible-to-the-app]] · [[Roadmap]]
