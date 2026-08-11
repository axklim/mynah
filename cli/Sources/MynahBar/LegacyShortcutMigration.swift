import Foundation
import KeyboardShortcuts

/// One-time migration that replaces a stale ⌃⌥C shortcut left over from before the
/// `.toggleCheck` default was changed to Hyper+C (⌃⌥⌘C).
///
/// Why this exists: `KeyboardShortcuts.Name.init` only writes its `default:` shortcut
/// into `UserDefaults` the first time a given name is seen — see the library's
/// `Name.swift`:
///
/// ```swift
/// public init(_ name: String, default initialShortcut: Shortcut? = nil) {
///     self.rawValue = name
///     self.defaultShortcut = initialShortcut
///     if let initialShortcut, !userDefaultsContains(name: self) {
///         setShortcut(initialShortcut, for: self)
///     }
///     KeyboardShortcuts.initialize()
/// }
/// ```
///
/// Once a value is persisted, the code default is never consulted again — and
/// `UserDefaults` is keyed by bundle identifier, so every build sharing
/// `io.klimov.mynah` reads/writes the same stored value. Machines that ran an
/// older build before the default changed are stuck on the old ⌃⌥C forever, even
/// after rebuilding with the new default in `Shortcuts.swift`.
///
/// Why this migration is deliberately narrow: once Phase 3 ships a shortcut recorder
/// UI, a user may deliberately choose ⌃⌥C again on purpose. This function must never
/// silently take that choice away. So it only resets the stored shortcut when it
/// matches the exact legacy value, and it only ever runs once per install (guarded by
/// a flag) — it must not keep re-asserting a preference on every launch.
@MainActor
func migrateLegacyToggleCheckShortcutIfNeeded() {
    let migrationFlagKey = "migratedToggleCheckToHyperC"
    let defaults = UserDefaults.standard

    guard !defaults.bool(forKey: migrationFlagKey) else {
        return
    }

    // Set the flag before doing anything else so this runs at most once per
    // install, even if a later step in this function returns early or is
    // modified in the future.
    defaults.set(true, forKey: migrationFlagKey)

    let legacyShortcut = KeyboardShortcuts.Shortcut(.c, modifiers: [.control, .option])
    guard KeyboardShortcuts.getShortcut(for: .toggleCheck) == legacyShortcut else {
        return
    }

    // reset (rather than setShortcut) writes the name's current default —
    // whatever Shortcuts.swift declares right now — instead of us hardcoding a
    // value here, so the migration cannot rot if the default changes again.
    KeyboardShortcuts.reset(.toggleCheck)
}
