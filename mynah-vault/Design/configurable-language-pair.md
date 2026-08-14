# Design — Configurable language pair (XDG config)

> Status: **shipped**, 2026-08-14. Brainstormed and implemented the same day; slots in as
> [[Roadmap|Phase 2.4]]. The CLI half (config parsing, `mynah translate`, `mynah config`) is verified
> end to end. The app half (`TranslateCoordinator`'s `makeTranslator` closure, the config-error panel
> state) shipped in code and is covered by the test suite, but the manual, hands-on-hotkey
> verification of it — including the `$XDG_CONFIG_HOME` divergence in
> [[xdg-config-invisible-to-the-app]] — is still **pending**.

The translator was hard-wired to **English → Russian** ([[ad-hoc-translator]]) — the direction lived
inside two prompt constants in `Sources/MynahCore/TextTranslator.swift`. This note made the pair a
setting, read from an XDG config file, and **changed the default to English → German**.

It also gives the project its first config file of any kind. That is the larger half of the work:
the language pair is two strings, but where they are read from, what happens when the file is
wrong, and which of the two products wins when they disagree are all decisions that outlive this
feature.

## Locked decisions

| Question | Decision |
|---|---|
| Default pair | **English → German**, replacing En → Ru. The old default is one config edit away. |
| How many pairs | **Exactly one active pair.** Changing language means editing the file — no `--to` flag, no menu picker, no second hotkey. |
| Configurable sides | **Both.** `source` and `target` are independent, so `German → English` is a config edit, not a code change. |
| Word-mode explanations | **The source language, kept simple.** Generalises today's behaviour: `en→de` keeps simple-English explanations and an English example. |
| Format | **`key = value` with `#` comments**, hand-parsed. No new dependency. |
| Language naming | **Plain English names** (`German`), passed into the prompt verbatim. No code table, so any language works on day one. |
| Where the pair enters | **The translator's initialiser.** The `TextTranslator` protocol is untouched. |
| `mynah check` | **Unchanged, English-only.** Out of scope — see below. |

### Why names, not codes

`de` is more conventional, but a code needs a `de → "German"` table in Core before the prompt can
say anything, and that table is a thing to maintain and a thing to be missing an entry from. The
consumer here is a natural-language prompt, which already understands "German" — and "Brazilian
Portuguese", which has no tidy two-letter code at all. The cost is that a typo becomes a strange
prompt rather than a validation error; the strictness rules below buy most of that back.

### Why one pair, and why no flag

Considered and rejected: a list of named pairs with a `Translate to ▸` submenu, and one global
hotkey per pair. Both answer "reach a second language *right now*", which is not the actual need —
the need is "this machine translates to German". A `--to` flag on the CLI is the cheapest of the
three and still deferred, because adding it later costs nothing and adding it now means designing
precedence between flag and file for a case that may never arrive.

## Approaches considered

| | Approach | Verdict |
|---|---|---|
| 1 | Config lives in Core; the pair is injected into `ClaudeCLITranslator`'s initialiser; the file is re-read per invocation | **Chosen** |
| 2 | The pair becomes a per-call protocol parameter — `translate(_:to:onStart:)` | Rejected: makes a future flag or picker nearly free, but changes the one interface the project deliberately froze ([[0006-polish-backend-claude-cli]]) for flexibility that was explicitly not wanted |
| 3 | `ClaudeCLITranslator` loads the config itself | Rejected: buries file I/O in a struct that is otherwise pure, points every test at the real `$HOME`, and leaves nowhere clean to report a malformed file |

---

## The config file

### Path

```
$XDG_CONFIG_HOME/mynah/config.conf      when set, non-empty, and absolute
~/.config/mynah/config.conf             otherwise
```

The env var is honoured only when it is an absolute path, per the XDG base directory spec — a
relative `XDG_CONFIG_HOME` is invalid and falls back rather than resolving against the current
directory, which for the app is a deliberately empty scratch directory
([[gui-claude-subprocess-tcc-prompt]]) and for the CLI is wherever you happened to be standing.

Resolution takes the environment and home directory **as parameters**, so tests exercise it without
touching the developer's real `$HOME`:

```swift
public static func path(environment: [String: String], home: URL) -> URL
```

> ⚠️ **The two products can disagree.** See [[xdg-config-invisible-to-the-app]]: a Finder- or
> `launchd`-launched `.app` inherits no shell environment, so `$XDG_CONFIG_HOME` is invisible to
> `Mynah.app` even when the `mynah` CLI in the same terminal can see it. They agree whenever the
> variable is unset, which is the normal case. Documented rather than papered over — the honest fix
> would be to ignore the variable entirely, which is worse.

### A missing file is not an error

It is the state of every fresh `brew install`, and it means the defaults: `English` → `German`,
model `sonnet`. Nothing is ever written to the user's home directory without being asked; the app
creating files in `~/.config` on first launch is both rude and a new permission surface.

A file that **exists but cannot be read** — wrong permissions, or not valid UTF-8 — is an error,
not a fallback to defaults. "Absent" is a deliberate state; "present and unreadable" is a problem
the user wants told about, and silently translating into the wrong language is the worst answer.

### Grammar

Strip `\r`, trim each line, skip blanks and lines starting with `#`, split on the **first** `=`.
`#` starts a comment **only at the start of a line** — there are no trailing comments, so
`target = German # my language` sets the target to `German # my language`. Supporting them would
mean deciding what a `#` inside a value means, for a file with three keys.
Keys are matched case-insensitively. Values keep internal spaces, so `Brazilian Portuguese` works,
and a matched pair of surrounding double quotes is stripped — `target = "German"` otherwise becomes
a language literally named `"German"`, which the model would probably still translate into,
so the mistake would never surface.

```
# Language of the text you paste.
source = English

# Language you want it in.
target = German

# Model passed to `claude --model`.
# model = sonnet
```

### It is strict on purpose

Every case below is an error naming the file and the line number. The whole failure mode of a
small hand-edited file is a typo that quietly does nothing, and this file is small enough that
strictness costs nothing:

| case | example |
|---|---|
| unknown key | `targt = Russian` |
| duplicate key | `target` set twice, one of them forgotten |
| no `=` on the line | `target German` |
| empty value | `target =` |
| `source` equal to `target` (case-insensitive) | `source = English` / `target = english` |
| a language name over 40 characters | you pasted something that is not a language name |

Both products ship from one release asset ([[0011-homebrew-tap-prebuilt]]), so an older binary can
never meet a newer config — there is no forward-compatibility argument for ignoring unknown keys.

`model` is **not** validated against a list of aliases: model names change, and a stale allowlist
rejects a model that works. It is passed to `claude --model` verbatim; a bad one fails at call
time, with claude's own message in the detail.

### Keys

| key | default | notes |
|---|---|---|
| `source` | `English` | The language you paste. Also the language of word-mode explanations and examples. |
| `target` | `German` | The language you want. |
| `model` | `sonnet` | Optional. The one key here that is not about languages — see below. |

`model` is included because it is three lines of code and it converts an open [[inbox]] item
(*"try Haiku for the translator's text mode"*) from a code change into a config edit. It is the
only scope beyond the language pair and can be cut without touching anything else.

### Errors surface where the config is used, never at launch

A broken config must not stop `Mynah.app` from launching, and must not break `mynah check`, which
does not read it. Concretely:

- **CLI** — `error: /Users/…/config.conf line 4: unknown key "targt"`, exit 2.
- **App** — the same sentence in the translation panel, which is already this feature's error
  surface ([[ad-hoc-translator]]). It gets its own `TranslationViewState` message rather than
  reusing "Couldn't reach claude.", which would be a lie.

### `mynah config`

Prints the resolved path as a comment, then the effective values, formatted as a valid config
file — stdout is a pure config file, nothing else, so it can be redirected straight to disk. When
the file does not exist, a "not found — showing defaults" note goes to **stderr** instead, so it
never ends up written into the config it is warning about:

```
$ mynah config
# /Users/aleksey/.config/mynah/config.conf
source = English
target = German
model = sonnet
```

Two jobs from one command: `mynah config` alone prints the effective settings, and
`mkdir -p ~/.config/mynah && mynah config > ~/.config/mynah/config.conf` is the init step for a
config file that does not exist yet. ⚠️ The shell truncates the target before `mynah` runs, so
re-running that same command against an existing (even broken) config reads it back empty and
silently overwrites it with defaults — use it once to create the file, then edit it directly.

---

## How it threads through

### Core

`Sources/MynahCore/MynahConfig.swift` — new, 205 lines:

```swift
public struct LanguagePair: Sendable, Equatable {
    public let source: String        // "English"
    public let target: String        // "German"
}

public struct MynahConfig: Sendable, Equatable {
    public let languages: LanguagePair
    public let model: String

    public static let `default` = MynahConfig(...)   // English → German, sonnet

    /// Reads and parses the file, or returns `.default` when it does not exist.
    public static func load(environment: [String: String], home: URL) throws -> MynahConfig
    /// Pure: the parser, tested without a filesystem.
    static func parse(_ text: String, path: String) throws -> MynahConfig
}

public struct ConfigError: Error, CustomStringConvertible { ... }   // path + line + reason
```

`Sources/MynahCore/TranslationPrompts.swift` — the two constants in `TextTranslator.swift` become
functions of the pair:

```swift
enum TranslationPrompts {
    static func text(_ pair: LanguagePair) -> String
    static func word(_ pair: LanguagePair) -> String
}
```

Word mode loses its *"You are helping a Russian-speaking software developer…"* opening: with the
pair configurable, the user's native language is no longer derivable from it — `de→en` says nothing
about who is reading. It becomes "a software developer", and the three fields are pinned to the
source language:

- `translation` — in **target**
- `explanation` — in simple **source**, about 15 words
- `example` — one short, natural **source** sentence

For the default `en→de` that is identical to today's teaching material, which is the point:
[[Spec]]'s purpose is improving the developer's *English*, and the English explanation is where
that happens.

`ClaudeCLITranslator(languages:model:)` takes both. `TextTranslator` itself does not change.

### CLI

`main.swift` loads the config at the top of `translate`, before the input guard, so a broken file is
reported without waiting on stdin. The `usage` string stops naming Russian and describes the
configured pair plus the config path. New `config` subcommand as above.

### App

`TranslateCoordinator`'s stored `translator: any TextTranslator` becomes:

```swift
makeTranslator: () throws -> any TextTranslator     // default: config → ClaudeCLITranslator
```

One injection point swapped for another, and two properties fall out of it: the file is re-read on
**every** hotkey press, so editing the config takes effect on the next press with no restart and no
"Reload config" menu item; and a `ConfigError` thrown at that point lands in the panel through the
path that already exists for rejections.

`ClaudeCLIEvaluator` and `CheckCoordinator` are untouched.

## Two slices

Each is separately verifiable, in the project's usual order — the terminal first, the GUI second
([[ad-hoc-translator]] made the same call, for the same reason: iterating on prompt wording through
a rebuilt `.app` costs minutes per attempt and debugs blind).

1. **Config in Core + the CLI.** `MynahConfig`, `TranslationPrompts`, the translator initialiser,
   `mynah translate` reading the file, and `mynah config`. Verifiable end to end in a terminal:
   the default returns German, an edit returns Russian, a typo exits 2 naming the line.
2. **The app.** `TranslateCoordinator`'s `makeTranslator` closure and the config-error state in the
   panel. Verifiable by editing the file and pressing the hotkey without restarting.

The doc updates ride with the slice that makes them true.

## Out of scope

- **`mynah check` stays English-only.** It evaluates the English *you are about to send* — the
  app's whole purpose ([[Spec]]) — so wiring `source` into it is a different decision, not a
  detail of this one.
- **A `--to` flag, a menu picker, per-pair hotkeys.** Rejected above; revisit if editing the file
  ever becomes annoying in practice.
- **Autodetecting the source.** Still the [[inbox]] item it was; this design makes the direction
  configurable, not automatic.
- **Anything else moving into the config file** (hotkeys, the 2000-character limit, the polish
  prompt). The file is a place for them later; nothing else moves now.

## Tests

Pure, no network, no real filesystem for the parser:

- **Parser** — comments, blank lines, spacing around `=`, quoted values, multi-word values, CRLF
  line endings, keys in mixed case, a value containing `=`, and one case per strict-error row above,
  asserting the reported line number.
- **Defaults** — absent file yields `English → German`; a file setting only `target` keeps the
  default `source`.
- **Path resolution** — `XDG_CONFIG_HOME` set to an absolute path, set to a relative path, set
  empty, and unset.
- **Prompts** — `TranslationPrompts.text`/`.word` for `en→de` and `de→en` name the right language
  in the right role; the word prompt asks for explanations in the source language.
- **`ConfigError` description** — reads as the sentence both products print.

## Manual verification

- No config file → `mynah translate "Could you take a look at my PR?"` returns German.
- `mynah config > …/config.conf`, then edit `target = Russian` → the same input returns Russian,
  **without rebuilding**.
- Same edit, then the Hyper+⇧C hotkey → Russian in the panel, **without restarting the app**.
- `targt = Russian` → CLI exits 2 naming line and key; the hotkey shows that sentence in the panel;
  `Mynah.app` still launches and Hyper+C still returns a verdict.
- Word mode with `source = English`, `target = German` → German translations, simple-English
  explanations and examples.
- `source = German`, `target = English`, paste German prose → English, and a single German word
  gives English translations with simple-German explanations.
- `XDG_CONFIG_HOME` set in the shell → confirm the CLI follows it and the app does not
  ([[xdg-config-invisible-to-the-app]]).

## Docs to update in the same commit

`CLAUDE.md` (the translator paragraph, the CLI target list, and the tech-decisions table, which has
no config row), `README.md`, `cli/README.md`, and `main.swift`'s `usage` all state "English →
Russian". In the vault: [[ad-hoc-translator]]'s locked-decisions table gains a superseded note on
the Direction row, [[Roadmap]] gains Phase 2.4, [[inbox]]'s autodetection item gains a pointer
here, and [[Home]] links this note plus two new files —
`Decisions/0012-xdg-config-language-pair.md` and `Findings/xdg-config-invisible-to-the-app.md`.

## Related

[[Home]] · [[Spec]] · [[Roadmap]] · [[ad-hoc-translator]] · [[0006-polish-backend-claude-cli]] ·
[[0011-homebrew-tap-prebuilt]] · [[gui-claude-subprocess-tcc-prompt]] · [[haiku-misses-ambiguity]] ·
[[inbox]]
