import AppKit

/// Menu-bar (accessory) app entry point. No storyboard, no Dock icon.
/// Lives in a non-`main.swift` file so we can use `@main`.
@main
@MainActor
struct MynahBarApp {
    static func main() {
        let app = NSApplication.shared
        // Retain the delegate for the whole run: NSApplication.delegate is weak,
        // and app.run() blocks until quit, so this local stays alive.
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu-bar only; no Dock icon
        app.run()
    }
}
