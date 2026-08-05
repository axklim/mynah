import AppKit
import KeyboardShortcuts
import SpellCheckerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusItemController!
    private var coordinator: CheckCoordinator!
    private var translateCoordinator: TranslateCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusItemController()
        coordinator = CheckCoordinator(status: status, evaluator: ClaudeCLIEvaluator())
        translateCoordinator = TranslateCoordinator(
            status: status,
            translator: ClaudeCLITranslator()
        )

        let menu = NSMenu()
        let checkItem = NSMenuItem(
            title: "Check clipboard now",
            action: #selector(checkNow),
            keyEquivalent: ""
        )
        checkItem.target = self
        menu.addItem(checkItem)
        let translateItem = NSMenuItem(
            title: "Translate clipboard now",
            action: #selector(translateNow),
            keyEquivalent: ""
        )
        translateItem.target = self
        menu.addItem(translateItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Spell Checker",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        status.setMenu(menu)

        migrateLegacyToggleCheckShortcutIfNeeded()

        // KeyboardShortcuts invokes the handler on the main thread; assumeIsolated
        // bridges it to our @MainActor coordinator across Swift 6 isolation checks.
        KeyboardShortcuts.onKeyDown(for: .toggleCheck) { [weak self] in
            MainActor.assumeIsolated {
                self?.coordinator.runCheck()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .translateClipboard) { [weak self] in
            MainActor.assumeIsolated {
                self?.translateCoordinator.runTranslate()
            }
        }
    }

    @objc private func checkNow() {
        coordinator.runCheck()
    }

    @objc private func translateNow() {
        translateCoordinator.runTranslate()
    }
}
