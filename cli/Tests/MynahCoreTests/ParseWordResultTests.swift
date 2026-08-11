import XCTest
@testable import MynahCore

final class ParseWordResultTests: XCTestCase {
    private func meanings(_ result: TranslationResult) -> [WordMeaning] {
        guard case .word(let meanings, _) = result else {
            XCTFail("expected word mode, got \(result)")
            return []
        }
        return meanings
    }

    private func hasMore(_ result: TranslationResult) -> Bool {
        guard case .word(_, let hasMore) = result else {
            XCTFail("expected word mode, got \(result)")
            return false
        }
        return hasMore
    }

    func testCleanJSON() throws {
        let reply = """
        {"meanings":[{"translation":"фиксация","explanation":"saving your changes into history","example":"I commit before lunch."}],"hasMore":false}
        """
        let result = try ClaudeCLITranslator.parseWordResult(from: reply)
        XCTAssertEqual(meanings(result).count, 1)
        XCTAssertEqual(meanings(result)[0].translation, "фиксация")
        XCTAssertEqual(meanings(result)[0].example, "I commit before lunch.")
        XCTAssertFalse(hasMore(result))
    }

    func testFencedJSON() throws {
        // claude wraps JSON in a markdown fence however firmly you ask it not to.
        let reply = """
        ```json
        {"meanings":[{"translation":"фиксация","explanation":"a saved change","example":"One commit per fix."}],"hasMore":true}
        ```
        """
        let result = try ClaudeCLITranslator.parseWordResult(from: reply)
        XCTAssertEqual(meanings(result).count, 1)
        XCTAssertTrue(hasMore(result))
    }

    func testJSONBehindLeadingProse() throws {
        let reply = """
        Here is the JSON you asked for:
        {"meanings":[{"translation":"обязательство","explanation":"a promise to do something","example":"That is a big commit of time."}],"hasMore":false}
        Hope that helps!
        """
        let result = try ClaudeCLITranslator.parseWordResult(from: reply)
        XCTAssertEqual(meanings(result)[0].translation, "обязательство")
    }

    func testMoreThanThreeMeaningsIsClampedAndForcesHasMore() throws {
        let one = #"{"translation":"a","explanation":"e","example":"x"}"#
        let reply = #"{"meanings":[\#(one),\#(one),\#(one),\#(one)],"hasMore":false}"#
        let result = try ClaudeCLITranslator.parseWordResult(from: reply)
        XCTAssertEqual(meanings(result).count, ClaudeCLITranslator.maxMeanings)
        XCTAssertTrue(hasMore(result), "dropping a meaning must be reported as more existing")
    }

    func testMissingHasMoreDefaultsToFalse() throws {
        let reply = #"{"meanings":[{"translation":"a","explanation":"e","example":"x"}]}"#
        XCTAssertFalse(hasMore(try ClaudeCLITranslator.parseWordResult(from: reply)))
    }

    func testZeroMeaningsThrows() {
        XCTAssertThrowsError(
            try ClaudeCLITranslator.parseWordResult(from: #"{"meanings":[],"hasMore":false}"#)
        )
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try ClaudeCLITranslator.parseWordResult(from: "{not json at all}"))
    }

    func testReplyWithNoJSONThrows() {
        XCTAssertThrowsError(try ClaudeCLITranslator.parseWordResult(from: "I cannot help with that."))
    }

    func testErrorMessageCarriesTheRawReply() {
        // The error text is the whole debugging path — no --raw flag exists.
        let reply = "I cannot help with that."
        do {
            _ = try ClaudeCLITranslator.parseWordResult(from: reply)
            XCTFail("expected a throw")
        } catch {
            XCTAssertTrue("\(error)".contains("cannot help"), "raw reply missing from: \(error)")
        }
    }
}
