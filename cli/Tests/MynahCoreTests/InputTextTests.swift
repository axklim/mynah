import XCTest
@testable import MynahCore

final class InputTextTests: XCTestCase {
    func testNilIsNoText() {
        XCTAssertEqual(InputText.check(nil), .noText)
    }

    func testEmptyIsNoText() {
        XCTAssertEqual(InputText.check(""), .noText)
    }

    func testWhitespaceOnlyIsNoText() {
        XCTAssertEqual(InputText.check("   \n\t  "), .noText)
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(InputText.check("  hello  \n"), .ok("hello"))
    }

    func testExactlyAtLimitIsOk() {
        let text = String(repeating: "a", count: InputText.characterLimit)
        XCTAssertEqual(InputText.check(text), .ok(text))
    }

    func testOneOverLimitIsTooLong() {
        let over = InputText.characterLimit + 1
        XCTAssertEqual(
            InputText.check(String(repeating: "a", count: over)),
            .tooLong(count: over)
        )
    }

    func testLimitAppliesAfterTrimming() {
        // Padding must not push an otherwise-legal payload over the limit.
        let payload = String(repeating: "a", count: InputText.characterLimit)
        XCTAssertEqual(InputText.check("  \n" + payload + "\n  "), .ok(payload))
    }

    func testCountsCharactersNotBytes() {
        // 1500 Cyrillic characters plus an em-dash: 1501 characters, but well
        // over 2000 UTF-8 bytes. A byte-based limit would wrongly reject this,
        // which is why the rule uses String.count.
        let text = String(repeating: "я", count: 1500) + "\u{2014}"
        XCTAssertEqual(text.count, 1501)
        XCTAssertGreaterThan(text.utf8.count, InputText.characterLimit)
        XCTAssertEqual(InputText.check(text), .ok(text))
    }
}
