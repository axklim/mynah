import XCTest
@testable import SpellCheckerCore

final class TranslationModeTests: XCTestCase {
    func testSingleWordIsWordMode() {
        XCTAssertEqual(TranslationMode.forInput("commit"), .word)
    }

    func testTwoWordsIsWordMode() {
        // A place name and a phrasal verb are both worth explaining as a unit.
        XCTAssertEqual(TranslationMode.forInput("New York"), .word)
        XCTAssertEqual(TranslationMode.forInput("look up"), .word)
    }

    func testHyphenatedWordIsOneWord() {
        XCTAssertEqual(TranslationMode.forInput("well-known"), .word)
    }

    func testThreeWordsIsTextMode() {
        XCTAssertEqual(TranslationMode.forInput("commit the change"), .text)
    }

    func testOddWhitespaceDoesNotChangeTheMode() {
        // Runs of spaces, tabs and newlines must not be counted as words.
        XCTAssertEqual(TranslationMode.forInput("  commit   the   change  "), .text)
        XCTAssertEqual(TranslationMode.forInput("commit\nthe\tchange"), .text)
        XCTAssertEqual(TranslationMode.forInput("  commit  "), .word)
    }

    func testEmptyInputIsWordMode() {
        // Unreachable through the CLI — InputText rejects empty input first — but
        // pinned so the split logic can never fall through to a crash.
        XCTAssertEqual(TranslationMode.forInput(""), .word)
        XCTAssertEqual(TranslationMode.forInput("   "), .word)
    }
}
