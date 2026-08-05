public extension TranslationResult {
    /// Render for a terminal.
    ///
    /// Text mode prints the Russian and nothing else, so the output can be piped
    /// straight into `pbcopy`. Word mode prints the source word as a header, then
    /// numbered meanings with the example quoted underneath.
    ///
    /// This lives in Core rather than in the CLI target because it is pure string
    /// work with no UI dependency, and an executable target cannot be imported by
    /// the test bundle — slice 1 learned that the hard way when an untestable
    /// mapping turned out to be the only thing distinguishing a green verdict from
    /// a red one.
    func terminalText(source: String) -> String {
        switch self {
        case .text(let russian):
            return russian

        case .word(let meanings, let hasMore):
            var lines = [source]
            for (index, meaning) in meanings.enumerated() {
                lines.append("  \(index + 1). \(meaning.translation) — \(meaning.explanation)")
                lines.append("     \"\(meaning.example)\"")
            }
            if hasMore {
                lines.append("  … more meanings exist")
            }
            return lines.joined(separator: "\n")
        }
    }
}
