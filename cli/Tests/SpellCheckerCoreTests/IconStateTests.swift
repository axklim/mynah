import XCTest
@testable import SpellCheckerCore

final class IconStateTests: XCTestCase {
    func testGlyphs() {
        XCTAssertEqual(IconState.neutral.glyph, "⚪")
        XCTAssertEqual(IconState.working.glyph, "⏳")
        XCTAssertEqual(IconState.empty.glyph, "📋")
        XCTAssertEqual(IconState.error.glyph, "⚠️")
        XCTAssertEqual(IconState.verdict(.green).glyph, "🟢")
        XCTAssertEqual(IconState.verdict(.yellow).glyph, "🟡")
        XCTAssertEqual(IconState.verdict(.red).glyph, "🔴")
    }

    func testIsTransient() {
        // neutral and working persist until replaced; the rest auto-revert.
        XCTAssertFalse(IconState.neutral.isTransient)
        XCTAssertFalse(IconState.working.isTransient)
        XCTAssertTrue(IconState.empty.isTransient)
        XCTAssertTrue(IconState.error.isTransient)
        XCTAssertTrue(IconState.verdict(.green).isTransient)
    }
}
