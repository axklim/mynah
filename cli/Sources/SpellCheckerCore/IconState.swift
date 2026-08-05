/// Colour applied to the status-item glyph.
///
/// A plain enum rather than an `NSColor` so `SpellCheckerCore` stays free of
/// AppKit; `StatusItemController` in the app target does the mapping. That also
/// makes the whole icon vocabulary swappable from one file.
public enum IconTint: Sendable, Equatable {
    /// The default label colour — follows light/dark appearance.
    case standard
    case green
    case yellow
    case red
    case orange
}

/// What the menu-bar icon shows. `verdict` wraps the traffic-light result so the
/// three colours share one case; the standalone cases cover the lifecycle.
public enum IconState: Sendable, Equatable {
    case neutral   // idle
    case working   // a check is running
    case empty     // clipboard had no text — nothing to check (NOT an error)
    case tooLong   // clipboard text is past the limit — almost surely a misclick
    case error     // claude failed or returned unparseable output
    case translating  // a translation is in flight; the panel is the real UI
    case verdict(Verdict)

    /// Nerd Font glyph (JetBrainsMonoNF-Regular), rendered as the status-item
    /// button's attributed title.
    ///
    /// Written as `\u{...}` escapes, **never** as pasted literal characters:
    /// these are private-use codepoints that corrupt when retyped out of a
    /// rendered terminal. The codepoints were chosen by rendering candidates and
    /// looking at them — Nerd Font glyph *names* do not survive the v2 → v3
    /// renumbering. See Findings/nerd-font-codepoint-identity.
    public var glyph: String {
        switch self {
        case .neutral: return "\u{f10c}"  // nf-fa-circle_o — hollow circle
        case .working: return "\u{f252}"  // nf-fa-hourglass_half
        case .empty:   return "\u{f016}"  // nf-fa-file_o — an empty page
        case .tooLong: return "\u{f02d}"  // nf-fa-book — "you copied a book"
        case .error:   return "\u{f071}"  // nf-fa-exclamation_triangle
        case .translating: return "\u{f05ca}"  // nf-md-translate — 文A
        case .verdict: return "\u{f111}"  // nf-fa-circle — colour carries the verdict
        }
    }

    /// Colour for `glyph`. `empty` and `tooLong` are untinted (not coloured
    /// like a verdict or error) but rendered at full contrast; the glyph shape
    /// carries the meaning. `tooLong` is deliberately *not* `error`: "you copied
    /// a whole page" and "claude broke" want different reactions.
    public var tint: IconTint {
        switch self {
        case .neutral, .working, .translating: return .standard
        case .empty, .tooLong:   return .standard
        case .error:             return .orange
        case .verdict(let v):
            switch v {
            case .green:  return .green
            case .yellow: return .yellow
            case .red:    return .red
            }
        }
    }

    /// Shown when the Nerd Font is not installed. Without a fallback, a missing
    /// font leaves an empty box where the app's only UI lives — and that is
    /// exactly the case for anyone installing via Homebrew.
    public var emojiGlyph: String {
        switch self {
        case .neutral: return "⚪"
        case .working: return "⏳"
        case .empty:   return "📋"
        case .tooLong: return "📏"
        case .error:   return "⚠️"
        case .translating: return "🔤"
        case .verdict(let v):
            switch v {
            case .green:  return "🟢"
            case .yellow: return "🟡"
            case .red:    return "🔴"
            }
        }
    }

    /// True for states that should auto-revert to `.neutral` after the display
    /// window; false for `.neutral` (the resting state), `.working`, and `.translating`
    /// (both replaced by the result, not by a timer).
    public var isTransient: Bool {
        switch self {
        case .neutral, .working, .translating: return false
        case .empty, .tooLong, .error, .verdict: return true
        }
    }

    /// Every state, for exhaustive tests. `IconState` cannot be `CaseIterable`
    /// because `verdict` carries an associated value.
    public static let allStates: [IconState] = [
        .neutral, .working, .empty, .tooLong, .error, .translating,
        .verdict(.green), .verdict(.yellow), .verdict(.red),
    ]
}
