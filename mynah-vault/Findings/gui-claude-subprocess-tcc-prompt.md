# Finding — the GUI app triggers a macOS privacy (TCC) prompt via the `claude` subprocess

## What happened

First time the menu-bar app ([[phase2-menubar-evaluator]]) ran a check after launch, macOS showed:

> **"Mynah.app" would like to access files in your Downloads folder.** — Don't Allow / Allow

The app itself never touches Downloads. The prompt comes from the **`claude` subprocess** we spawn:
`claude` (Claude Code) **inspects its working directory on startup** to establish a "project."
When the `.app` is launched from Finder, its working directory is a user folder, so `claude`
reading it trips macOS **TCC** (Transparency, Consent & Control) — the same machinery behind the
Documents/Desktop/Downloads access prompts.

## Why it's surprising

It looks like *our* app is snooping user files, but it's an inherited-CWD side effect of shelling
out to a CLI that is directory-aware. The CLI prototype never showed this — a terminal-launched
process runs in the terminal's CWD with the user's normal file-access context, so no prompt.

## Fix (shipped) — isolate the subprocess working directory

`claude` inspects its **working directory** on startup (git status, `CLAUDE.md`, directory
listing). The real fix is to give it an **empty, app-private** CWD so it has nothing around to
scan or absorb — the verdict then depends only on the stdin prompt:

```swift
// ClaudeCLIEvaluator.claudeWorkingDirectory()
let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
let dir = support.appendingPathComponent("Mynah/claude-cwd", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
// → process.currentDirectoryURL = dir
```

**Do NOT use `FileManager.default.temporaryDirectory`** — that returns the *shared* per-user
`$TMPDIR` (`/var/folders/.../T/`), which on a real machine holds hundreds of other apps' files
(~900 MB here). It's not TCC-protected, but it's the opposite of "nothing to scan." A dedicated,
empty dir under Application Support (not TCC-protected; stable path so workspace-trust persists)
is the correct version.

## Caveat — this does NOT reliably remove the TCC prompt

The temp-dir change was first shipped *as a TCC fix*; that framing was wrong. The macOS prompt
("Mynah.app would like to access … Downloads") is attributed to our app via TCC's
responsible-process chain, but the access originates inside `claude`, and
[anthropics/claude-code#61233](https://github.com/anthropics/claude-code/issues/61233) shows
Claude Code can probe Desktop/Documents/Downloads/iCloud **independent of CWD**. So pinning CWD may
*reduce* but not eliminate the prompt. Two compounding facts: `-p` mode skips the workspace-trust
dialog (good — no hang), but our `.app` is **ad-hoc signed**, so its identity changes every
`make app` and TCC grants don't persist across rebuilds. **Decision for now:** accept the
occasional prompt (click Allow); the value of the empty-CWD change is *isolation*, not prompt
suppression. To actually confirm/diagnose the prompt: `tccutil reset SystemPolicyDownloadsFolder
io.klimov.mynah && make run-app`, then watch `log stream --predicate 'subsystem ==
"com.apple.TCC"'`.

## Takeaway

When a GUI app shells out to a **directory-aware CLI** (`claude`, `git`, build tools…), give it an
explicit, **empty, app-private** `currentDirectoryURL` — not an inherited user folder *and not the
shared `$TMPDIR`*. The primary win is **isolation** (the subprocess can't read or absorb whatever
files happen to be around — important when the tool's output should depend only on our input); a
secondary, *partial* effect is fewer macOS file-access prompts. Related:
[[0006-polish-backend-claude-cli]] (the `claude -p` backend) and the PATH-from-Finder wrinkle in
[[phase2-menubar-evaluator]].

## Related

[[Home]] · [[phase2-menubar-evaluator]] · [[0006-polish-backend-claude-cli]]
