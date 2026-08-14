import XCTest
@testable import MynahCore

final class TranslationPromptsTests: XCTestCase {
    private let enToDe = LanguagePair(source: "English", target: "German")
    private let deToEn = LanguagePair(source: "German", target: "English")

    func testTextPromptNamesBothLanguagesInTheRightRoles() {
        let prompt = TranslationPrompts.text(enToDe)
        XCTAssertTrue(prompt.contains("Translate the following English text into German"), prompt)
        XCTAssertTrue(prompt.contains("ONLY the German translation"), prompt)
    }

    func testTextPromptFlipsWithThePair() {
        let prompt = TranslationPrompts.text(deToEn)
        XCTAssertTrue(prompt.contains("Translate the following German text into English"), prompt)
    }

    func testWordPromptAsksForTranslationsInTheTarget() {
        let prompt = TranslationPrompts.word(enToDe)
        XCTAssertTrue(prompt.contains("the German translation"), prompt)
    }

    func testWordPromptAsksForExplanationsInTheSource() {
        // Locked decision: explanation and example follow the SOURCE language, so
        // the default pair keeps today's simple-English teaching material.
        let prompt = TranslationPrompts.word(enToDe)
        XCTAssertTrue(prompt.contains("in simple English"), prompt)
        XCTAssertTrue(prompt.contains("natural English sentence"), prompt)
    }

    func testWordPromptExplanationsFlipWithThePair() {
        let prompt = TranslationPrompts.word(deToEn)
        XCTAssertTrue(prompt.contains("in simple German"), prompt)
        XCTAssertTrue(prompt.contains("natural German sentence"), prompt)
        XCTAssertTrue(prompt.contains("the English translation"), prompt)
    }

    func testWordPromptNoLongerAssumesTheReaderIsRussianSpeaking() {
        // With the pair configurable, the user's native language is not derivable
        // from it — `de→en` says nothing about who is reading.
        XCTAssertFalse(TranslationPrompts.word(enToDe).contains("Russian"))
    }

    func testWordPromptStillPinsTheJSONShape() {
        let prompt = TranslationPrompts.word(enToDe)
        XCTAssertTrue(prompt.contains("\"hasMore\""), prompt)
        XCTAssertTrue(prompt.contains("minified JSON"), prompt)
    }

    func testTranslatorTakesItsPairFromAConfig() {
        let config = MynahConfig(
            languages: LanguagePair(source: "German", target: "English"),
            model: "haiku"
        )
        let translator = ClaudeCLITranslator(config)
        XCTAssertEqual(translator.languages, config.languages)
        XCTAssertEqual(translator.model, "haiku")
    }
}
