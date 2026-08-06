/// A traffic-light verdict on a piece of text.
///
/// red vs. yellow is a *comprehension* line: red means a reader might
/// misunderstand; yellow means they'll understand but it reads non-native.
public enum Verdict: String, Sendable {
    case red, yellow, green

    public var display: String {
        switch self {
        case .red:    return "🔴 red"
        case .yellow: return "🟡 yellow"
        case .green:  return "🟢 green"
        }
    }
}
