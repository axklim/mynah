# Finding — `$XDG_CONFIG_HOME` can be invisible to `Mynah.app`, same root cause as the `PATH` finding

## The claim

A Finder- or `launchd`-launched `.app` inherits no shell environment. So a `$XDG_CONFIG_HOME` set in
`~/.zshrc` (or any interactive-shell rc) is visible to the `mynah` CLI, which runs inside that shell —
but invisible to `Mynah.app`, which runs as a child of Finder/`launchd` and never sourced the rc at
all. When that happens, the app silently reads `~/.config/mynah/config.conf` (the fallback in
[[configurable-language-pair]]) while the CLI in the very same terminal reads whatever
`$XDG_CONFIG_HOME` points to.

This is **the same root cause** as [[gui-claude-subprocess-tcc-prompt]]'s `PATH` problem: a GUI app
launched outside a shell does not get the shell's environment, full stop. That finding already
established this for `PATH`; environment variables in general work the same way, so `XDG_CONFIG_HOME`
was expected to behave identically before any config-specific testing happened.

## What is actually verified, and what is not

**Verified — the CLI half.** Confirmed 2026-08-14 with `MynahConfig.path`/`load`:

```
$ mkdir -p /tmp/mynah-xdg/mynah
$ printf 'target = French\n' > /tmp/mynah-xdg/mynah/config.conf
$ XDG_CONFIG_HOME=/tmp/mynah-xdg swift run mynah config
# /tmp/mynah-xdg/mynah/config.conf
source = English
target = French
model = sonnet
```

The CLI followed the variable to a path outside `~/.config` and read the file there. This is real,
reproducible evidence, not an inference.

**Not verified — the app half.** This needs pressing Hyper+⇧C on the already-running `Mynah.app` with
`$XDG_CONFIG_HOME` pointed at a different config and watching whether the floating panel translates
to French (the app saw the variable) or German (it didn't, and fell back to
`~/.config/mynah/config.conf`). That is a hands-on, human-in-front-of-the-screen check and has not
been performed as part of this pass. The expectation that the app resolves to the fallback path
follows from the documented mechanism in [[gui-claude-subprocess-tcc-prompt]] — it is not something
this pass observed happening. Treat the app half as **pending**, not confirmed, until someone runs it.

## The divergence is conditional, not currently active

On the machine this was written on, the developer's shell has `XDG_CONFIG_HOME=/Users/aleksey/.config`
set — an **absolute** path, so the CLI honours it per [[configurable-language-pair]]'s resolution
rule. That happens to resolve to `/Users/aleksey/.config/mynah/config.conf`, which is exactly the same
file `~/.config/mynah/config.conf` names. So today, on this machine, the CLI and the app read the
identical file regardless of whether the app can see the environment variable — there is nothing to
disagree about. The divergence only becomes observable when `$XDG_CONFIG_HOME` points somewhere
**other** than `~/.config` (the `/tmp/mynah-xdg` case above), which is not this developer's everyday
setup. Do not read this note as "the two products currently disagree" — they don't, right now, here.
It is a real edge once someone's `$XDG_CONFIG_HOME` diverges from the default, and worth having
written down before that day arrives.

## Rejected fixes

- **Ignore the variable entirely, always read `~/.config/mynah/config.conf`.** Removes the
  divergence by removing the feature: the CLI is the one place `$XDG_CONFIG_HOME` reliably works, and
  punishing that user (who followed the XDG spec on purpose) to make the GUI's ignorance symmetric is
  the worse trade.
- **Read the shell rc directly to recover the variable for the app.** Fragile — which rc, which
  shell, and a value set via `direnv`, a subshell, or a conditional in the rc may not appear in a
  static read at all — and surprising: an app parsing the user's shell startup files is a bigger,
  weirder footprint than the one config file it's trying to locate.

## Accepted: document it

No code changes. [[configurable-language-pair]] and `cli/README.md`'s Configuration section both
call this out as a documented caveat rather than a papered-over bug. The honest fix is knowing about
it, not hiding it.

## Related

[[Home]] · [[configurable-language-pair]] · [[0012-xdg-config-language-pair]] ·
[[gui-claude-subprocess-tcc-prompt]]
