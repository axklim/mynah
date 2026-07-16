/// What the menu-bar icon shows. `verdict` wraps the traffic-light result so the
/// three colours share one case; the standalone cases cover the lifecycle.
public enum IconState: Sendable, Equatable {
    case neutral   // idle
    case working   // a check is running
    case empty     // clipboard had no text — nothing to check (NOT an error)
    case error     // claude failed or returned unparseable output
    case verdict(Verdict)

    /// Emoji rendered as the status-item button title.
    public var glyph: String {
        switch self {
        case .neutral: return "⚪"
        case .working: return "⏳"
        case .empty:   return "📋"
        case .error:   return "⚠️"
        case .verdict(let v):
            switch v {
            case .green:  return "🟢"
            case .yellow: return "🟡"
            case .red:    return "🔴"
            }
        }
    }

    /// True for states that should auto-revert to `.neutral` after the display
    /// window; false for `.neutral` (the resting state) and `.working` (replaced
    /// by the result, not by a timer).
    public var isTransient: Bool {
        switch self {
        case .neutral, .working: return false
        case .empty, .error, .verdict: return true
        }
    }
}
