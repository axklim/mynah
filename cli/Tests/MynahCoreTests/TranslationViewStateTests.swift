import XCTest
import MynahCore
@testable import MynahUI

final class TranslationViewStateTests: XCTestCase {
    func testTextResultBecomesTextState() {
        let state = TranslationViewState.from(.text("Привет, мир."), source: "Hello, world.")
        guard case .text(let russian) = state else { return XCTFail("expected .text, got \(state)") }
        XCTAssertEqual(russian, "Привет, мир.")
    }

    func testWordResultCarriesTheSourceAsHeader() {
        // The source word is the header, so the panel shows what you looked up.
        let meaning = WordMeaning(translation: "фиксация", explanation: "a saved change", example: "One commit per fix.")
        let state = TranslationViewState.from(.word(meanings: [meaning], hasMore: true), source: "commit")
        guard case .word(let source, let meanings, let hasMore) = state else {
            return XCTFail("expected .word, got \(state)")
        }
        XCTAssertEqual(source, "commit")
        XCTAssertEqual(meanings, [meaning])
        XCTAssertTrue(hasMore)
    }

    func testNoTextRejectionReadsAsASentence() {
        guard case .failed(let message)? = TranslationViewState.rejection(.noText) else {
            return XCTFail("expected a rejection state for .noText")
        }
        XCTAssertEqual(message, "Nothing to translate — the clipboard has no text.")
    }

    func testTooLongRejectionNamesBothNumbers() {
        // Naming the count and the limit is what tells the user whether the paste
        // or the limit is the problem.
        guard case .failed(let message)? = TranslationViewState.rejection(.tooLong(count: 4820)) else {
            return XCTFail("expected a rejection state for .tooLong")
        }
        XCTAssertTrue(message.contains("4820"), "missing the count: \(message)")
        XCTAssertTrue(message.contains("\(InputText.characterLimit)"), "missing the limit: \(message)")
    }

    func testOkIsNotARejection() {
        XCTAssertNil(TranslationViewState.rejection(.ok("fine")))
    }

    func testFailureMessageWrapsAnUnderlyingError() {
        struct Boom: Error, CustomStringConvertible { let description = "socket closed" }
        guard case .failed(let message) = TranslationViewState.failure(Boom()) else {
            return XCTFail("expected .failed")
        }
        XCTAssertTrue(message.hasPrefix("Couldn't reach claude."), "wrong lead: \(message)")
        XCTAssertTrue(message.contains("socket closed"), "detail dropped: \(message)")
    }
}
