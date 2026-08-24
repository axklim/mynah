import XCTest
@testable import MynahCore

final class MynahConfigFileTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/someone")

    /// A unique empty directory per test, removed in tearDown.
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("mynah-config-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        scratch = nil
    }

    /// Write `text` to `<scratch>/.config/mynah/config.conf` and return a home
    /// directory pointing at the scratch dir.
    private func writeConfig(_ text: String) throws -> URL {
        let dir = scratch.appendingPathComponent(".config/mynah", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: dir.appendingPathComponent("config.conf"))
        return scratch
    }

    // MARK: - Path resolution

    func testUsesXDGConfigHomeWhenAbsolute() {
        let url = MynahConfig.path(environment: ["XDG_CONFIG_HOME": "/opt/cfg"], home: home)
        XCTAssertEqual(url.path, "/opt/cfg/mynah/config.conf")
    }

    func testFallsBackWhenXDGConfigHomeIsRelative() {
        // A relative XDG_CONFIG_HOME is invalid per the spec, and resolving it
        // against the current directory would mean the app reads its own private
        // scratch dir.
        let url = MynahConfig.path(environment: ["XDG_CONFIG_HOME": "cfg"], home: home)
        XCTAssertEqual(url.path, "/Users/someone/.config/mynah/config.conf")
    }

    func testFallsBackWhenXDGConfigHomeIsEmpty() {
        let url = MynahConfig.path(environment: ["XDG_CONFIG_HOME": ""], home: home)
        XCTAssertEqual(url.path, "/Users/someone/.config/mynah/config.conf")
    }

    func testFallsBackWhenXDGConfigHomeIsUnset() {
        let url = MynahConfig.path(environment: [:], home: home)
        XCTAssertEqual(url.path, "/Users/someone/.config/mynah/config.conf")
    }

    // MARK: - Loading

    func testMissingFileYieldsDefaults() throws {
        let config = try MynahConfig.load(environment: [:], home: scratch)
        XCTAssertEqual(config, .default)
    }

    func testReadsAFileFromDisk() throws {
        let home = try writeConfig("target = Russian\nmodel = haiku\n")
        let config = try MynahConfig.load(environment: [:], home: home)
        XCTAssertEqual(config.languages, LanguagePair(source: "English", target: "Russian"))
        XCTAssertEqual(config.model, "haiku")
    }

    func testXDGConfigHomeWins() throws {
        let dir = scratch.appendingPathComponent("xdg/mynah", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("target = Russian".utf8).write(to: dir.appendingPathComponent("config.conf"))
        _ = try writeConfig("target = French")

        let config = try MynahConfig.load(
            environment: ["XDG_CONFIG_HOME": scratch.appendingPathComponent("xdg").path],
            home: scratch
        )
        XCTAssertEqual(config.languages.target, "Russian")
    }

    func testParseErrorsCarryTheRealPath() throws {
        let home = try writeConfig("targt = Russian")
        XCTAssertThrowsError(try MynahConfig.load(environment: [:], home: home)) {
            let error = $0 as? ConfigError
            XCTAssertEqual(error?.line, 1)
            XCTAssertTrue(
                error?.path.hasSuffix(".config/mynah/config.conf") == true,
                "path was \(error?.path ?? "nil")"
            )
        }
    }

    func testAPathThatIsADirectoryIsAnError() throws {
        // `fileExists` says yes for a directory, so this is the branch where the
        // file is present but unreadable — the one case that must not fall back
        // to defaults.
        try FileManager.default.createDirectory(
            at: scratch.appendingPathComponent(".config/mynah/config.conf", isDirectory: true),
            withIntermediateDirectories: true
        )
        XCTAssertThrowsError(try MynahConfig.load(environment: [:], home: scratch)) {
            let error = $0 as? ConfigError
            XCTAssertNil(error?.line)
            XCTAssertTrue(
                error?.reason.contains("could not be read") == true,
                "reason was \(error?.reason ?? "nil")"
            )
        }
    }

    func testFileThatIsNotUTF8IsAnError() throws {
        let dir = scratch.appendingPathComponent(".config/mynah", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 0xFF is not valid UTF-8 in any position.
        try Data([0x74, 0x61, 0xFF]).write(to: dir.appendingPathComponent("config.conf"))

        XCTAssertThrowsError(try MynahConfig.load(environment: [:], home: scratch)) {
            let error = $0 as? ConfigError
            XCTAssertNil(error?.line)
            XCTAssertTrue(error?.reason.contains("UTF-8") == true, "reason was \(error?.reason ?? "nil")")
        }
    }

    // MARK: - `mynah config` output

    func testConfigFileTextNamesThePath() {
        let text = MynahConfig.default.configFileText(path: "/tmp/config.conf")
        XCTAssertTrue(text.hasPrefix("# /tmp/config.conf\n"), "text was \(text)")
    }

    func testConfigFileTextNeverMentionsWhetherTheFileExists() {
        // `configFileText` no longer takes an `exists` flag: the "not found" note
        // moved to the CLI's stderr (main.swift's `config` case, untestable here —
        // an executable target cannot be imported by the test bundle) so that
        // stdout is a pure config file. This guards against the note creeping
        // back into the text `configFileText` renders.
        let text = MynahConfig.default.configFileText(path: "/tmp/config.conf")
        XCTAssertFalse(text.contains("not found"), "text was \(text)")
    }

    func testConfigFileTextRoundTrips() throws {
        // `mynah config > ~/.config/mynah/config.conf` must produce a file that
        // parses back to exactly the same settings.
        let config = MynahConfig(
            languages: LanguagePair(source: "German", target: "Brazilian Portuguese"),
            model: "haiku",
            translationFocusGraceSeconds: 5
        )
        let text = config.configFileText(path: "/tmp/config.conf")
        XCTAssertEqual(try MynahConfig.parse(text, path: "/tmp/config.conf"), config)
    }
}
