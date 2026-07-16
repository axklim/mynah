import AppKit
import SpellCheckerCore

/// Owns the menu-bar status item and renders an `IconState`. Transient states
/// auto-revert to `.neutral` after `displayDuration`.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private var revertTimer: Timer?
    private let displayDuration: TimeInterval = 4

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = IconState.neutral.glyph
    }

    func setMenu(_ menu: NSMenu) { statusItem.menu = menu }

    /// Render `state`. Any pending revert is cancelled first, so a fresh result
    /// (or a new `.working`) restarts the cycle cleanly.
    func show(_ state: IconState) {
        revertTimer?.invalidate()
        revertTimer = nil
        statusItem.button?.title = state.glyph
        guard state.isTransient else { return }
        revertTimer = Timer.scheduledTimer(
            withTimeInterval: displayDuration, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.show(.neutral) }
        }
    }
}
