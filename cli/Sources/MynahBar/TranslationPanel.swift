import AppKit
import SwiftUI
import MynahUI

/// The floating translation window.
///
/// Dismissal is covered from two angles because it is two different events: Esc
/// arrives as `cancelOperation(_:)` and needs the panel to be key, which is why
/// `show` calls `NSApp.activate`. Focus loss is handled by the `resignKey()`
/// override — and since the app deactivating also resigns the panel's key status,
/// that path likely fires `resignKey()` too; `hidesOnDeactivate` is a backstop on
/// top of it, not a separate, non-overlapping mechanism.
@MainActor
final class TranslationPanel {
    private let onDismiss: () -> Void
    private var panel: KeyPanel?

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    /// Show the panel, creating it if needed, and make it key so Esc arrives.
    ///
    /// Reuses an open panel rather than stacking a second one: pressing the hotkey
    /// while a result is on screen replaces the contents.
    func show(_ state: TranslationViewState) {
        let panel = panel ?? makePanel()
        self.panel = panel
        render(state, into: panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Swap the content of an already-visible panel. Does nothing if it is closed,
    /// so a late reply cannot resurrect a dismissed window.
    func update(_ state: TranslationViewState) {
        guard let panel, panel.isVisible else { return }
        render(state, into: panel)
    }

    /// Host the state and size the window to what it actually needs.
    ///
    /// **Why the explicit sizing.** A `ScrollView` does not shrink to its content the
    /// way a `VStack` does, so without this the panel would open at its full
    /// `maxHeight` for every state — a one-line Russian sentence in a 420×520 window
    /// with most of it empty. The panel therefore asks the hosting view what it wants
    /// (`fittingSize`) and clamps the answer: never taller than `maxHeight`, and never
    /// so short that the loading row has nowhere to sit.
    private func render(_ state: TranslationViewState, into panel: KeyPanel) {
        let host = NSHostingView(rootView: TranslationView(state: state))
        panel.contentView = host
        let wanted = host.fittingSize.height
        let height = min(max(wanted, Self.minContentHeight), TranslationPanelMetrics.maxHeight)
        panel.setContentSize(NSSize(width: TranslationPanelMetrics.width, height: height))
        position(panel)
    }

    /// Enough for the loading row plus padding, so a short state still reads as a
    /// window rather than a sliver.
    private static let minContentHeight: CGFloat = 72

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(
            // Initial size only; `render` resizes to the content before it is shown.
            contentRect: NSRect(
                x: 0, y: 0,
                width: TranslationPanelMetrics.width,
                height: Self.minContentHeight
            ),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.onCancelOrResignKey = { [weak self] in self?.handleDismissal() }
        return panel
    }

    /// Guards against re-entry: `close()` on a key panel resigns key synchronously,
    /// which calls straight back into this method. Without the guard one Esc press
    /// would fire `onDismiss` twice, and the coordinator's contract is one dismissal
    /// to one reset.
    private var isDismissing = false

    private func handleDismissal() {
        guard !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }

        panel?.close()
        // Hand focus back to whatever the developer was reading.
        NSApp.hide(nil)
        onDismiss()
    }

    /// Horizontally centred on the active screen, in the upper third —
    /// Spotlight-like and predictable, rather than chasing a mouse that had nothing
    /// to do with pressing a keyboard shortcut.
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.maxY - visible.height / 3 - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// An `NSPanel` that reports Esc and loss of key status to its owner.
@MainActor
final class KeyPanel: NSPanel {
    var onCancelOrResignKey: (() -> Void)?

    /// Esc arrives here rather than as a keyDown, provided the panel is key.
    override func cancelOperation(_ sender: Any?) {
        onCancelOrResignKey?()
    }

    override func resignKey() {
        super.resignKey()
        onCancelOrResignKey?()
    }
}
