# Finding — a `KeyboardShortcuts` code-default change is not a rebind

- **Date:** 2026-08-04
- **Context:** Task 7 rebound `.toggleCheck`'s default from ⌃⌥C to ⌃⌥⌘C (Hyper+C) in
  `Shortcuts.swift` ([[ad-hoc-translator]] Slice 1). After rebuilding and relaunching, ⌃⌥⌘C did
  nothing and the old ⌃⌥C still worked.

## What happened

The code change was correct and the rebuild picked it up — no build errors, the new default sat
right there in `Shortcuts.swift` — but the running app kept responding to the *old* shortcut.
Editing a default that has no visible effect on a freshly rebuilt app looks like a build/cache
problem, not a persistence one, so the first look went to the wrong layer.

## Wrong suspect — Karabiner

*(One detail explains why Karabiner was the natural first suspect: on this machine, Karabiner
remaps the corner `fn` key alone to emit ⌃⌥⌘, so `fn`+C is how the shortcut is actually pressed
day to day. A remap sitting in the input path is an obvious place to look when a hotkey
misbehaves.)*

A Karabiner-EventViewer dump of the physical key press showed `c` arriving with flags
`left_control, left_option, left_command` — exactly ⌃⌥⌘C, correctly remapped, correctly delivered
to the app. Karabiner was doing its job. Ruled out.

## Actual cause — `UserDefaults` persistence in `KeyboardShortcuts.Name.init`

`defaults read io.klimov.spellchecker` told the real story:

```
$ defaults read io.klimov.spellchecker
{
    "KeyboardShortcuts_toggleCheck" = "{\"carbonKeyCode\":8,\"carbonModifiers\":6144}";
}
```

The real preference key is `KeyboardShortcuts_toggleCheck`, and the value is a **JSON string**, not
a plist dictionary — `carbonKeyCode` and `carbonModifiers` are fields inside that JSON, not their
own plist keys. `6144` decodes as `controlKey (4096) + optionKey (2048)` — with no `cmdKey (256)`.
The persisted shortcut was still the **old** ⌃⌥C, byte for byte, regardless of what
`Shortcuts.swift` now said.

The library's own `Name.swift` explains why:

```swift
public init(_ name: String, default initialShortcut: Shortcut? = nil) {
    self.rawValue = name
    self.defaultShortcut = initialShortcut
    if let initialShortcut, !userDefaultsContains(name: self) {
        setShortcut(initialShortcut, for: self)
    }
    KeyboardShortcuts.initialize()
}
```

The `default:` argument is only ever consulted **once** — the first time that `Name` is seen with
nothing already stored. Every earlier run of this app (before the rebind shipped) had already
written ⌃⌥C into `UserDefaults`. Once written, the code default is dead weight: changing it in
source doesn't touch the stored value, so every later launch reads the old shortcut straight back
out.

Compounding it: `UserDefaults` is a per-**bundle-identifier** domain, not per-build or per-version.
Every build of this app shares `io.klimov.spellchecker`, so a debug build, a `make app` release
build, and an old binary kept around for testing all read and write the *same* stored shortcut.
But `Name.init`'s guard is `!userDefaultsContains(name: self)` — it only *writes* when nothing is
stored yet. So an older build re-seeds ⌃⌥C only when the stored key is **absent**; with Hyper+C
already persisted, an older build *reads* that value back and binds Hyper+C too, same as the new
build would.

**The actual recovery hazard is narrower, and worse in a different way.** If the stored key is ever
absent again — e.g. `defaults delete` while debugging, then launching an older build first — that
older build re-seeds the legacy ⌃⌥C. `LegacyShortcutMigration` sets its one-shot flag
*unconditionally*, before it compares the stored shortcut to the legacy value, so the migration
runs at most once per preferences domain, full stop. If the new build's migration already ran
before this happens, it returns early on the flag check and never looks at the (now legacy again)
stored value — Hyper+C is silently dead, with **no in-app recovery**. The fix is to delete the
stored key by hand.

That one-shot flag is nonetheless the right design: it is what protects a deliberate rebinding once
the Phase 3 shortcut-recorder UI ships — the migration must not keep re-asserting Hyper+C over a
choice the user made on purpose. When that UI ships, this migration should be **deleted rather than
inherited**, not left to complicate a real rebind flow.

## Fix

Task 8b: a one-time migration (`migrateLegacyToggleCheckShortcutIfNeeded`, guarded by a
`migratedToggleCheckToHyperC` flag) resets the stored shortcut back to the current default — but
only when the stored value is *exactly* the legacy ⌃⌥C, so a future deliberate rebind via the
Phase 3 recorder UI is never silently overridden by this migration.

## Takeaway

- **Changing a code default is not a rebind.** `KeyboardShortcuts.Name(_:default:)` — and any
  library with the same "seed on first sight" pattern — writes the default once, ever, per stored
  domain. A machine that ran a previous version already has its own stored value and will never
  see the new default without an explicit migration.
- **Diagnostic to reach for first**, before re-litigating the input path: `defaults read
  <bundle-id>` to see what's actually persisted, then decode the carbon modifier mask by hand —
  `controlKey = 4096`, `optionKey = 2048`, `cmdKey = 256`, `shiftKey = 512` — rather than trusting
  what the code *should* have produced.
- Karabiner-EventViewer is the right tool to rule out the remap layer, but it answers "what key
  event arrived at the app", not "what shortcut the app is listening for" — two different failure
  domains that look identical from the keyboard.

## Related

[[ad-hoc-translator]] · [[0002-invocation-menubar-hotkey]] · [[phase2-menubar-evaluator]]
