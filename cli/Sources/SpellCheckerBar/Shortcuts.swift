import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global hotkey that triggers a clipboard check. Default: ⌃⌥C.
    /// User-rebindable recorder UI is deferred (see vault inbox).
    @MainActor static let toggleCheck = Self(
        "toggleCheck",
        default: .init(.c, modifiers: [.control, .option])
    )
}
