import XCTest
@testable import MynahCore

final class MynahConfigParseTests: XCTestCase {
    private let path = "/Users/someone/.config/mynah/config.conf"

    // MARK: - Defaults and happy paths

    func testEmptyTextIsAllDefaults() throws {
        let config = try MynahConfig.parse("", path: path)
        XCTAssertEqual(config, .default)
        XCTAssertEqual(config.languages.source, "English")
        XCTAssertEqual(config.languages.target, "German")
        XCTAssertEqual(config.model, "sonnet")
    }

    func testReadsBothLanguages() throws {
        let config = try MynahConfig.parse("source = German\ntarget = English", path: path)
        XCTAssertEqual(config.languages, LanguagePair(source: "German", target: "English"))
    }

    func testOnlyTargetSetKeepsTheDefaultSource() throws {
        let config = try MynahConfig.parse("target = Russian", path: path)
        XCTAssertEqual(config.languages, LanguagePair(source: "English", target: "Russian"))
        XCTAssertEqual(config.model, "sonnet")
    }

    func testCommentsAndBlankLinesAreIgnored() throws {
        let text = """
        # Language of the text you paste.
        source = English

           # indented comment

        target = German
        """
        XCTAssertEqual(try MynahConfig.parse(text, path: path), .default)
    }

    func testToleratesSpacingAroundEquals() throws {
        let config = try MynahConfig.parse("source=German\n   target   =   English   ", path: path)
        XCTAssertEqual(config.languages, LanguagePair(source: "German", target: "English"))
    }

    func testKeysAreCaseInsensitive() throws {
        let config = try MynahConfig.parse("TARGET = Russian\nModel = haiku", path: path)
        XCTAssertEqual(config.languages.target, "Russian")
        XCTAssertEqual(config.model, "haiku")
    }

    func testStripsOneMatchedPairOfSurroundingQuotes() throws {
        // Without this, the language is literally `"German"` and the model would
        // probably still translate into it — so the mistake would never surface.
        let config = try MynahConfig.parse("target = \"German\"", path: path)
        XCTAssertEqual(config.languages.target, "German")
    }

    func testKeepsInternalSpacesInValues() throws {
        let config = try MynahConfig.parse("target = Brazilian Portuguese", path: path)
        XCTAssertEqual(config.languages.target, "Brazilian Portuguese")
    }

    func testHashOnlyStartsACommentAtTheStartOfALine() throws {
        // No trailing comments: deciding what a `#` inside a value means is not
        // worth it for a file with three keys.
        let config = try MynahConfig.parse("target = German # my language", path: path)
        XCTAssertEqual(config.languages.target, "German # my language")
    }

    func testValueCanContainAnEqualsSign() throws {
        // Splitting on the *first* `=` is a deliberate grammar decision, not an
        // accident — a value like this is a strange language name, but nothing
        // about the grammar forbids it.
        let config = try MynahConfig.parse("target = C# and a = sign", path: path)
        XCTAssertEqual(config.languages.target, "C# and a = sign")
    }

    func testHandlesCRLFLineEndings() throws {
        let config = try MynahConfig.parse("source = German\r\ntarget = English\r\n", path: path)
        XCTAssertEqual(config.languages, LanguagePair(source: "German", target: "English"))
    }

    // MARK: - Strictness

    func testUnknownKeyIsAnErrorNamingTheLine() {
        XCTAssertThrowsError(try MynahConfig.parse("source = English\ntargt = Russian", path: path)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 2)
            XCTAssertEqual(error?.path, self.path)
            XCTAssertTrue(error?.reason.contains("targt") == true, "reason was \(error?.reason ?? "nil")")
        }
    }

    func testDuplicateKeyIsAnErrorNamingBothLines() {
        XCTAssertThrowsError(try MynahConfig.parse("target = German\ntarget = Russian", path: path)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 2)
            XCTAssertTrue(error?.reason.contains("line 1") == true, "reason was \(error?.reason ?? "nil")")
        }
    }

    func testLineWithoutEqualsIsAnError() {
        XCTAssertThrowsError(try MynahConfig.parse("target German", path: path)) {
            XCTAssertEqual(($0 as? ConfigError)?.line, 1)
        }
    }

    func testEmptyValueIsAnError() {
        XCTAssertThrowsError(try MynahConfig.parse("\ntarget =", path: path)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 2)
            XCTAssertTrue(error?.reason.contains("target") == true, "reason was \(error?.reason ?? "nil")")
        }
    }

    func testSourceEqualToTargetIsAnErrorIgnoringCase() {
        XCTAssertThrowsError(try MynahConfig.parse("source = English\ntarget = english", path: path)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 2)
            XCTAssertTrue(error?.reason.contains("english") == true, "reason was \(error?.reason ?? "nil")")
        }
    }

    func testDefaultSourceCollidingWithAnExplicitTargetIsAnError() {
        // `target = English` alone collides with the default source.
        XCTAssertThrowsError(try MynahConfig.parse("target = English", path: path))
    }

    func testOverlongLanguageNameIsAnError() {
        let long = String(repeating: "a", count: MynahConfig.maxLanguageNameLength + 1)
        XCTAssertThrowsError(try MynahConfig.parse("target = \(long)", path: path)) {
            XCTAssertEqual(($0 as? ConfigError)?.line, 1)
        }
    }

    func testModelIsNotValidatedAgainstAList() throws {
        // Model names change; a stale allowlist rejects a model that works.
        let config = try MynahConfig.parse("model = claude-opus-4-1", path: path)
        XCTAssertEqual(config.model, "claude-opus-4-1")
    }

    // MARK: - translationFocusGraceSeconds

    func testDefaultTranslationFocusGraceSecondsIsSixty() throws {
        let config = try MynahConfig.parse("", path: path)
        XCTAssertEqual(config.translationFocusGraceSeconds, 60)
    }

    func testReadsTranslationFocusGraceSeconds() throws {
        let config = try MynahConfig.parse("translationFocusGraceSeconds = 5", path: path)
        XCTAssertEqual(config.translationFocusGraceSeconds, 5)
    }

    func testTranslationFocusGraceSecondsZeroIsAllowed() throws {
        // 0 reproduces the original instant-close-on-focus-loss behaviour.
        let config = try MynahConfig.parse("translationFocusGraceSeconds = 0", path: path)
        XCTAssertEqual(config.translationFocusGraceSeconds, 0)
    }

    func testNegativeTranslationFocusGraceSecondsIsAnError() {
        XCTAssertThrowsError(
            try MynahConfig.parse("translationFocusGraceSeconds = -1", path: path)
        ) {
            XCTAssertEqual(($0 as? ConfigError)?.line, 1)
        }
    }

    func testNonIntegerTranslationFocusGraceSecondsIsAnError() {
        XCTAssertThrowsError(
            try MynahConfig.parse("translationFocusGraceSeconds = soon", path: path)
        ) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 1)
            XCTAssertTrue(
                error?.reason.contains("translationfocusgraceseconds") == true,
                "reason was \(error?.reason ?? "nil")"
            )
        }
    }

    // MARK: - Error rendering

    func testErrorDescriptionNamesPathLineAndReason() {
        let error = ConfigError(path: path, line: 4, reason: "unknown key \"targt\"")
        XCTAssertEqual(error.description, "\(path) line 4: unknown key \"targt\"")
    }

    func testErrorDescriptionWithoutALineOmitsIt() {
        let error = ConfigError(path: path, line: nil, reason: "is not valid UTF-8")
        XCTAssertEqual(error.description, "\(path): is not valid UTF-8")
    }
}
