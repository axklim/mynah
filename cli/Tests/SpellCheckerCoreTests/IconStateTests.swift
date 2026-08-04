import XCTest
@testable import SpellCheckerCore

final class IconStateTests: XCTestCase {
    func testGlyphs() {
        // Nerd Font codepoints, written as escapes. Chosen by rendering them —
        // see Findings/nerd-font-codepoint-identity.
        XCTAssertEqual(IconState.neutral.glyph, "\u{f10c}")          // hollow circle
        XCTAssertEqual(IconState.working.glyph, "\u{f252}")          // hourglass
        XCTAssertEqual(IconState.empty.glyph, "\u{f016}")            // outlined page
        XCTAssertEqual(IconState.tooLong.glyph, "\u{f02d}")          // closed book
        XCTAssertEqual(IconState.error.glyph, "\u{f071}")            // warning triangle
        XCTAssertEqual(IconState.verdict(.green).glyph, "\u{f111}")  // filled circle
        XCTAssertEqual(IconState.verdict(.yellow).glyph, "\u{f111}")
        XCTAssertEqual(IconState.verdict(.red).glyph, "\u{f111}")
    }

    func testGlyphsAreSingleScalars() {
        // Guards against a pasted literal sneaking in: emoji like "⚠️" are two
        // scalars (base + variation selector), Nerd Font glyphs are always one.
        for state in IconState.allStates {
            XCTAssertEqual(
                state.glyph.unicodeScalars.count, 1,
                "\(state) glyph must be exactly one Unicode scalar"
            )
        }
    }

    func testTints() {
        // The three verdicts share one glyph and differ only by colour.
        XCTAssertEqual(IconState.neutral.tint, .standard)
        XCTAssertEqual(IconState.working.tint, .standard)
        XCTAssertEqual(IconState.empty.tint, .standard)
        XCTAssertEqual(IconState.tooLong.tint, .standard)
        XCTAssertEqual(IconState.error.tint, .orange)
        XCTAssertEqual(IconState.verdict(.green).tint, .green)
        XCTAssertEqual(IconState.verdict(.yellow).tint, .yellow)
        XCTAssertEqual(IconState.verdict(.red).tint, .red)
    }

    func testEmojiFallback() {
        // Used when the Nerd Font is missing, so the icon is never an empty box.
        XCTAssertEqual(IconState.neutral.emojiGlyph, "⚪")
        XCTAssertEqual(IconState.working.emojiGlyph, "⏳")
        XCTAssertEqual(IconState.empty.emojiGlyph, "📋")
        XCTAssertEqual(IconState.tooLong.emojiGlyph, "📏")
        XCTAssertEqual(IconState.error.emojiGlyph, "⚠️")
        XCTAssertEqual(IconState.verdict(.green).emojiGlyph, "🟢")
        XCTAssertEqual(IconState.verdict(.yellow).emojiGlyph, "🟡")
        XCTAssertEqual(IconState.verdict(.red).emojiGlyph, "🔴")
    }

    func testIsTransient() {
        // neutral and working persist until replaced; the rest auto-revert.
        XCTAssertFalse(IconState.neutral.isTransient)
        XCTAssertFalse(IconState.working.isTransient)
        XCTAssertTrue(IconState.empty.isTransient)
        XCTAssertTrue(IconState.tooLong.isTransient)
        XCTAssertTrue(IconState.error.isTransient)
        XCTAssertTrue(IconState.verdict(.green).isTransient)
    }

    func testAllStatesIsExhaustive() {
        // If a case is added without extending allStates, the coverage test in
        // IconFontCoverageTests would silently stop checking it.
        XCTAssertEqual(IconState.allStates.count, 8)
        for state in IconState.allStates {
            XCTAssertFalse(state.glyph.isEmpty)
            XCTAssertFalse(state.emojiGlyph.isEmpty)
        }
    }
}
