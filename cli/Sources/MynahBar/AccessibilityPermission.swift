import ApplicationServices
import Foundation

@MainActor
func requestAccessibilityPermissionIfNeeded() {
    let requestedFlagKey = "requestedAccessibilityForGlobalEscape"
    let defaults = UserDefaults.standard

    guard !defaults.bool(forKey: requestedFlagKey) else { return }
    defaults.set(true, forKey: requestedFlagKey)

    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}
