# mynah — CLI evaluator + menu-bar app

Evaluates a message and returns **one** traffic-light verdict — 🔴 / 🟡 / 🟢 — and nothing else.
It does not rewrite the text.

- 🟢 **green** — clear, natural, safe to send as is.
- 🟡 **yellow** — understandable, but worth fixing (awkward / non-native / grammar slips).
- 🔴 **red** — a reader might misunderstand it (unclear, ambiguous, or a double meaning).

`red` is **comprehension-only**: grammar mistakes alone stay yellow as long as the meaning is
clear. Criteria + prompt:
[traffic-light-eval](../mynah-vault/Design/traffic-light-eval.md).

Backend: `claude -p --model sonnet` (Claude Code CLI in print mode) behind a `TextEvaluator`
abstraction — no API key needed. See
[Decision 0006](../mynah-vault/Decisions/0006-polish-backend-claude-cli.md) and
[Decision 0007](../mynah-vault/Decisions/0007-traffic-light-evaluator-first.md).

## Requirements

- Swift 6 toolchain (Command Line Tools is enough — no Xcode).
- The `claude` CLI installed and authenticated (`claude -p` must work).

## Install

From the repo root:

```sh
make install          # builds release, installs `mynah` to ~/.local/bin
```

Override the location with `make install PREFIX=/usr/local`; remove with `make uninstall`.

## Usage

```sh
mynah check "Please send the file to Anna and her assistant when she is ready."
# → 🔴 red

pbpaste | mynah check
echo "Thanks for the review, I've merged the branch." | mynah check
# → 🟢 green

mynah --help
```

Prints just the verdict to stdout; errors go to stderr with a non-zero exit code. Input over 2000
characters is rejected as a likely misclick (`InputText.characterLimit` in
`MynahCore`).

```
mynah translate <text>     Translate between the configured language pair (default English → German)
mynah translate            Read the text from stdin
```

```
$ mynah translate commit
commit
  1. sich verpflichten — to promise or dedicate yourself firmly to a plan, relationship, or course of action
     "She decided to commit to the new job offer."
  2. committen — to save a set of code changes permanently to a version control repository
     "I need to commit these changes before I switch branches."
  3. begehen — to carry out a crime or serious wrongdoing
     "He was accused of committing fraud."
  … more meanings exist
```

The final line appears only when the word has further common meanings that were left out.

Direction is whatever the config file says (default English → German); there is no autodetection,
so pasting text in the wrong language is undefined. Three or more words return the translation
alone, which is what makes `pbpaste | mynah translate | pbcopy` round-trip cleanly.

## Configuration

Translation reads `$XDG_CONFIG_HOME/mynah/config.conf`, falling back to
`~/.config/mynah/config.conf`. The environment variable is honoured only when it is an absolute
path; relative values fall back to `~/.config/mynah/config.conf` instead. Without a file, the pair is **English → German**.

```
# Language of the text you paste.
source = English

# Language you want it in.
target = German

# Model passed to `claude --model`.
# model = sonnet
```

`mynah config` prints the effective settings as a valid config file, so
`mkdir -p ~/.config/mynah && mynah config > ~/.config/mynah/config.conf` writes a
starter. Only use it to create the file the first time: the shell truncates the target before
`mynah` runs, so re-running the same command against an existing config reads it back empty and
silently overwrites it with defaults. Languages are plain English names — `Brazilian Portuguese`
works.

The file is parsed strictly: an unknown key, a duplicate key, an empty value, or
`source` equal to `target` is an error naming the line. `#` starts a comment only
at the start of a line. `mynah check` does not read this file.

The menu-bar app re-reads it on every hotkey press, so an edit takes effect
without restarting. One caveat: a Finder- or `launchd`-launched app inherits no
shell environment, so `$XDG_CONFIG_HOME` is invisible to `Mynah.app` even when
the CLI in your terminal can see it. They agree whenever it is unset.

## Dev (without installing)

```sh
cd cli && swift run mynah check "some text"
```

## Menu-bar app (Phase 2)

A menu-bar app wraps the same evaluator. Press **⌃⌥⌘C** (Control+Option+Command+C, "Hyper+C") to
evaluate whatever is on the clipboard; the tray icon shows the verdict for ~4s, then reverts:

Hollow circle = idle · hourglass = checking · green / yellow / red dot = verdict · outlined page =
clipboard empty · book = text over 2000 characters · warning triangle = error. These are
JetBrainsMono Nerd Font glyphs; install the font (`brew install --cask font-jetbrains-mono-nerd-font`)
or the app falls back to emoji: ⚪ ⏳ 🟢 🟡 🔴 📋 📏 ⚠️.

Press **⌃⌥⌘⇧C** (Hyper+⇧C) to translate the clipboard between the configured language pair (default
English → German) in a floating window, re-reading the config on every press so an edit takes effect
without restarting. One or two words return up to three meanings with explanations in the source
language and examples; three or more words return just the translation. Esc — or clicking into
another app — dismisses the window and cancels the call. Because the window is this feature's whole
UI, an empty or oversized clipboard — or a broken config file — is reported as a sentence inside it
rather than as a menu-bar icon.

```sh
make app        # build dist/Mynah.app
make run-app    # build and open it
```

It's an accessory app (no Dock icon) and quits from its menu. The shortcut is hardcoded for now;
a rebind UI is planned (see the vault inbox). Dev run without bundling: `cd cli && swift run mynah-bar`.

## Swapping the backend later

Implement another `TextEvaluator` (e.g. a litellm / Gemini backend) and use it in `main.swift`.
Nothing else changes.
