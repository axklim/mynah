import AppKit
import SpellCheckerCore

/// The one place `IconTint` becomes an `NSColor`. `.standard` uses
/// `labelColor` (not black) so the icon follows light and dark appearance.
public func nsColor(for tint: IconTint) -> NSColor {
    switch tint {
    case .standard:  return .labelColor
    case .green:     return .systemGreen
    case .yellow:    return .systemYellow
    case .red:       return .systemRed
    case .orange:    return .systemOrange
    }
}
