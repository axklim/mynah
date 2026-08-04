import AppKit
import SpellCheckerCore
import SpellCheckerUI

/// Owns the menu-bar status item and renders an `IconState`. Transient states
/// auto-revert to `.neutral` after `displayDuration`.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private var revertTimer: Timer?
    private let displayDuration: TimeInterval = 4

    /// Nerd Font used for the glyphs — see `IconFont.postScriptName` for why
    /// this name and not the Mono variant. nil when the font is not installed
    /// — see `render(_:)`.
    private static let glyphFont = NSFont(name: IconFont.postScriptName, size: glyphPointSize)

    /// Both values were tuned against the real menu bar; Nerd Font metrics are
    /// built for a terminal cell, so the glyphs need a nudge to sit on the menu
    /// bar's optical centre.
    private static let glyphPointSize: CGFloat = 15
    private static let glyphBaselineOffset: CGFloat = -1

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render(.neutral)
    }

    func setMenu(_ menu: NSMenu) { statusItem.menu = menu }

    /// Render `state`. Any pending revert is cancelled first, so a fresh result
    /// (or a new `.working`) restarts the cycle cleanly.
    func show(_ state: IconState) {
        revertTimer?.invalidate()
        revertTimer = nil
        render(state)
        guard state.isTransient else { return }
        revertTimer = Timer.scheduledTimer(
            withTimeInterval: displayDuration, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.show(.neutral) }
        }
    }

    private func render(_ state: IconState) {
        guard let button = statusItem.button else { return }

        // Without the font the glyphs would render as empty boxes, so fall back
        // to the emoji vocabulary rather than showing nothing at all.
        guard let font = Self.glyphFont else {
            button.attributedTitle = NSAttributedString(string: state.emojiGlyph)
            return
        }

        button.attributedTitle = NSAttributedString(
            string: state.glyph,
            attributes: [
                .font: font,
                .foregroundColor: nsColor(for: state.tint),
                .baselineOffset: Self.glyphBaselineOffset,
            ]
        )
    }
}
