import XCTest
@testable import SpellCheckerCore

final class TranslationTerminalTests: XCTestCase {
    func testTextModePrintsTheRussianAlone() {
        // So `pbpaste | spell-checker translate | pbcopy` round-trips cleanly.
        let result = TranslationResult.text("Привет, мир.")
        XCTAssertEqual(result.terminalText(source: "Hello, world."), "Привет, мир.")
    }

    func testWordModeIsNumberedWithQuotedExamples() {
        let result = TranslationResult.word(
            meanings: [
                WordMeaning(
                    translation: "фиксация",
                    explanation: "saving your changes into the repository history",
                    example: "I commit my changes before lunch."
                ),
                WordMeaning(
                    translation: "обязательство",
                    explanation: "a promise to do something",
                    example: "This is a big commit of time."
                ),
            ],
            hasMore: false
        )
        XCTAssertEqual(result.terminalText(source: "commit"), """
        commit
          1. фиксация — saving your changes into the repository history
             "I commit my changes before lunch."
          2. обязательство — a promise to do something
             "This is a big commit of time."
        """)
    }

    func testMoreLineAppearsOnlyWhenHasMore() {
        let one = WordMeaning(translation: "а", explanation: "e", example: "x")
        let without = TranslationResult.word(meanings: [one], hasMore: false)
        let with = TranslationResult.word(meanings: [one], hasMore: true)
        XCTAssertFalse(without.terminalText(source: "a").contains("more meanings exist"))
        XCTAssertTrue(with.terminalText(source: "a").hasSuffix("  … more meanings exist"))
    }
}
