import Foundation

/// The outcome of checking raw input before spending an LLM call on it.
public enum InputCheck: Sendable, Equatable {
    /// Usable input, already trimmed. Callers should use this value.
    case ok(String)
    /// Nil, empty, or whitespace only — nothing to work with. Not an error.
    case noText
    /// Past the character limit; almost always a misclick (a whole page pasted).
    case tooLong(count: Int)
}

/// One input rule shared by every surface: the CLI, the menu-bar check, and
/// (from slice 2) the translator. Each surface renders the rejections its own
/// way — stderr, an icon, or a line in a window — but the rule lives here.
public enum InputText {
    /// Maximum accepted length, in characters.
    ///
    /// Sized to sit above any real message (a long Slack post or PR description
    /// runs a few hundred to a couple of thousand characters) while rejecting an
    /// accidental full-page paste, which lands in the tens of thousands.
    public static let characterLimit = 2000

    /// Trim `raw`, then classify it.
    ///
    /// Counts **characters** (`String.count`), not bytes. Em-dashes and arrows
    /// already make the two diverge, and Cyrillic costs two UTF-8 bytes per
    /// character — a byte limit would silently halve any Russian text.
    public static func check(_ raw: String?) -> InputCheck {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noText }
        let count = trimmed.count
        guard count <= characterLimit else { return .tooLong(count: count) }
        return .ok(trimmed)
    }
}
