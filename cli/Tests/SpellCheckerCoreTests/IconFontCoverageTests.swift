import AppKit
import CoreText
import XCTest
@testable import SpellCheckerCore

final class IconFontCoverageTests: XCTestCase {
    /// The font `StatusItemController` asks for, shared via `IconFont` in
    /// `SpellCheckerCore` so the two names cannot drift apart.
    private static let fontName = IconFont.postScriptName

    func testFontCoversEveryDeclaredGlyph() throws {
        guard let font = NSFont(name: Self.fontName, size: 15) else {
            throw XCTSkip("\(Self.fontName) is not installed — the app falls back to emoji")
        }

        // CTFontCopyCharacterSet, NOT CTFontGetGlyphsForCharacters: the latter
        // works in UTF-16 code units, so every codepoint above U+FFFF arrives as
        // a surrogate pair and reports "missing" — a false negative that covers
        // the entire Material Design block in Nerd Fonts v3.
        // See Findings/nerd-font-codepoint-identity.
        let covered = CTFontCopyCharacterSet(font as CTFont) as CharacterSet

        for state in IconState.allStates {
            for scalar in state.glyph.unicodeScalars {
                let hex = String(scalar.value, radix: 16, uppercase: true)
                XCTAssertTrue(
                    covered.contains(scalar),
                    "\(Self.fontName) has no glyph for U+\(hex) (\(state))"
                )
            }
        }
    }
}
