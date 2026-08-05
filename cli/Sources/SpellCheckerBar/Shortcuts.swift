import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global hotkey that triggers a clipboard check. Default: Hyper+C (⌃⌥⌘C).
    ///
    /// Changing this default is enough to rebind: `KeyboardShortcuts` only reads
    /// it when no user-set shortcut is stored in UserDefaults, and nothing in the
    /// app writes one (there is no recorder UI yet — see the vault inbox). The
    /// name string is the UserDefaults key and must stay `"toggleCheck"`.
    /// Slice 3 adds a second name for the translator (⌃⌥⌘⇧C).
    @MainActor static let toggleCheck = Self(
        "toggleCheck",
        default: .init(.c, modifiers: [.control, .option, .command])
    )

    /// Global hotkey that translates the clipboard into the floating window.
    /// Default: Hyper+⇧C (⌃⌥⌘⇧C) — the checker's Hyper+C plus Shift.
    ///
    /// A fresh name, so no stored value exists for it and the code default applies.
    /// Note what slice 1 learned the hard way: `KeyboardShortcuts` writes this
    /// default into UserDefaults on first launch, and from then on the stored value
    /// wins — see Findings/keyboardshortcuts-persists-its-default. Changing it later
    /// needs a migration, not just an edit here.
    @MainActor static let translateClipboard = Self(
        "translateClipboard",
        default: .init(.c, modifiers: [.control, .option, .command, .shift])
    )
}
