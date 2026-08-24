public extension MynahConfig {
    /// Render the effective settings **as a valid config file**, so
    /// `mynah config > ~/.config/mynah/config.conf` is the init step and the
    /// output doubles as documentation of where the file lives. Only use it to
    /// create the file the first time: the redirect truncates the target before
    /// `mynah` runs, so re-running it against an existing config reads back
    /// empty and silently overwrites it with defaults.
    ///
    /// Lives in Core rather than in the CLI target because an executable target
    /// cannot be imported by the test bundle — same reason as
    /// `TranslationResult.terminalText(source:)`.
    func configFileText(path: String) -> String {
        """
        # \(path)
        source = \(languages.source)
        target = \(languages.target)
        model = \(model)
        translationFocusGraceSeconds = \(translationFocusGraceSeconds)
        """
    }
}
