import AppKit

/// The clipboard's text, or nil when it holds none.
///
/// A non-text clipboard (an image) yields nil, which `InputText.check` already
/// classifies as `.noText` — so both coordinators treat "an image" and "nothing"
/// the same way, deliberately.
func clipboardText() -> String? {
    NSPasteboard.general.string(forType: .string)
}
