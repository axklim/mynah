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
}
