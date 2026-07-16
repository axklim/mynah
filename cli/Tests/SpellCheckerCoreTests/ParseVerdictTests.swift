import XCTest
@testable import SpellCheckerCore

final class ParseVerdictTests: XCTestCase {
    func testPlainWord() throws {
        XCTAssertEqual(try ClaudeCLIEvaluator.parseVerdict(from: "green"), .green)
    }

    func testCaseInsensitiveWithSurroundingText() throws {
        XCTAssertEqual(try ClaudeCLIEvaluator.parseVerdict(from: "The verdict is RED."), .red)
    }

    func testEmojiPrefixed() throws {
        XCTAssertEqual(try ClaudeCLIEvaluator.parseVerdict(from: "🟡 yellow"), .yellow)
    }

    func testIgnoresSubstrings() throws {
        // "covered" contains "red" as a substring but is not a standalone token.
        XCTAssertEqual(
            try ClaudeCLIEvaluator.parseVerdict(from: "I covered everything; verdict: green"),
            .green
        )
    }

    func testNoVerdictThrows() {
        XCTAssertThrowsError(try ClaudeCLIEvaluator.parseVerdict(from: "no idea here"))
    }

    func testVerdictDisplay() {
        XCTAssertEqual(Verdict.red.display, "🔴 red")
        XCTAssertEqual(Verdict.yellow.display, "🟡 yellow")
        XCTAssertEqual(Verdict.green.display, "🟢 green")
    }
}
