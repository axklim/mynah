import AppKit
import Carbon.HIToolbox
import SwiftUI
import MynahUI
import MynahCore

@MainActor
final class TranslationPanel {
    private let onDismiss: () -> Void
    private let focusGraceSeconds: () -> Int
    private var panel: KeyPanel?
    private var graceTimer: Timer?
    private var globalEscapeMonitor: Any?

    init(onDismiss: @escaping () -> Void, focusGraceSeconds: @escaping () -> Int) {
        self.onDismiss = onDismiss
        self.focusGraceSeconds = focusGraceSeconds
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == kVK_Escape else { return }
            Task { @MainActor in self?.handleGlobalEscape() }
        }
    }

    func show(_ state: TranslationViewState) {
        let panel = panel ?? makePanel()
        self.panel = panel
        render(state, into: panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func update(_ state: TranslationViewState) {
        guard let panel, panel.isVisible else { return }
        render(state, into: panel)
    }

    private func render(_ state: TranslationViewState, into panel: KeyPanel) {
        let host = NSHostingView(rootView: TranslationView(state: state))
        panel.contentView = host
        let wanted = host.fittingSize.height
        let height = min(max(wanted, Self.minContentHeight), TranslationPanelMetrics.maxHeight)
        panel.setContentSize(NSSize(width: TranslationPanelMetrics.width, height: height))
        position(panel)
    }

    private static let minContentHeight: CGFloat = 72

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(
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
        // resignKey() already covers app deactivation; leaving this on would
        // hide the panel before the grace timer gets a chance.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.onExplicitClose = { [weak self] in self?.handleDismissal() }
        panel.onResignKey = { [weak self] in self?.startGraceTimer() }
        panel.onBecomeKey = { [weak self] in self?.cancelGraceTimer() }
        return panel
    }

    private var isDismissing = false

    private func handleDismissal() {
        guard !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }

        cancelGraceTimer()
        panel?.close()
        NSApp.hide(nil)
        onDismiss()
    }

    private func startGraceTimer() {
        guard !isDismissing else { return }
        cancelGraceTimer()
        let seconds = focusGraceSeconds()
        guard seconds > 0 else {
            handleDismissal()
            return
        }
        graceTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDismissal()
            }
        }
    }

    private func cancelGraceTimer() {
        graceTimer?.invalidate()
        graceTimer = nil
    }

    private func handleGlobalEscape() {
        guard let panel, panel.isVisible else { return }
        handleDismissal()
    }

    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.maxY - visible.height / 3 - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class KeyPanel: NSPanel {
    var onExplicitClose: (() -> Void)?
    var onResignKey: (() -> Void)?
    var onBecomeKey: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onExplicitClose?()
    }

    override func close() {
        onExplicitClose?()
        super.close()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }
}
