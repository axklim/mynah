import Foundation

/// Which language the developer pastes, and which one they want it in.
///
/// Plain English names ("German", "Brazilian Portuguese"), not ISO codes: the
/// only consumer is a natural-language prompt, which already understands them,
/// so there is no table to maintain and no language missing from it.
public struct LanguagePair: Sendable, Equatable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

/// Everything `~/.config/mynah/config.conf` can say.
///
/// The file is optional: its absence is the state of every fresh `brew install`
/// and simply means `.default`. A file that exists but cannot be read is an
/// error, because silently translating into the wrong language is the worst
/// possible answer to "your config is broken".
public struct MynahConfig: Sendable, Equatable {
    public let languages: LanguagePair
    /// Passed to `claude --model` verbatim — but only reaches the translator;
    /// `ClaudeCLIEvaluator` keeps its own hard-coded `sonnet` and never reads this.
    /// Deliberately not validated against a list of aliases: model names change,
    /// and a stale allowlist rejects a model that works.
    public let model: String

    public init(languages: LanguagePair, model: String) {
        self.languages = languages
        self.model = model
    }

    public static let `default` = MynahConfig(
        languages: LanguagePair(source: "English", target: "German"),
        model: "sonnet"
    )

    /// Longer than this is not a language name, it is a stray paste.
    static let maxLanguageNameLength = 40

    private static let knownKeys: Set<String> = ["source", "target", "model"]

    /// Parse `key = value` lines. Pure — the `path` is only ever used to build
    /// error messages, so the parser is testable without a filesystem.
    ///
    /// Strict on purpose: the whole failure mode of a small hand-edited file is a
    /// typo that quietly does nothing. Both products ship from one release asset
    /// (Decision 0011), so an older binary can never meet a newer config — there
    /// is no forward-compatibility argument for ignoring unknown keys.
    static func parse(_ text: String, path: String) throws -> MynahConfig {
        var values: [String: String] = [:]
        var lineOf: [String: Int] = [:]

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for (index, rawLine) in normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).enumerated() {
            let number = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // `#` comments only at the start of a line — no trailing comments, so
            // there is never a question about what a `#` inside a value means.
            if line.isEmpty || line.hasPrefix("#") { continue }

            guard let equals = line.firstIndex(of: "=") else {
                throw ConfigError(
                    path: path,
                    line: number,
                    reason: "expected `key = value`, found \(line.debugDescription)"
                )
            }

            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = unquoted(
                String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            )

            guard knownKeys.contains(key) else {
                throw ConfigError(
                    path: path,
                    line: number,
                    reason: "unknown key \(key.debugDescription) — expected source, target or model"
                )
            }
            guard !value.isEmpty else {
                throw ConfigError(path: path, line: number, reason: "\(key) has no value")
            }
            if let first = lineOf[key] {
                throw ConfigError(
                    path: path,
                    line: number,
                    reason: "\(key) is already set on line \(first)"
                )
            }

            values[key] = value
            lineOf[key] = number
        }

        let source = values["source"] ?? Self.default.languages.source
        let target = values["target"] ?? Self.default.languages.target

        for (key, value) in [("source", source), ("target", target)]
        where value.count > maxLanguageNameLength {
            throw ConfigError(
                path: path,
                line: lineOf[key],
                reason: "\(key) is \(value.count) characters — that is not a language name"
            )
        }

        guard source.lowercased() != target.lowercased() else {
            throw ConfigError(
                path: path,
                line: lineOf["target"] ?? lineOf["source"],
                reason: "source (\(source.debugDescription)) and target (\(target.debugDescription)) "
                    + "are the same — there would be nothing to translate"
            )
        }

        return MynahConfig(
            languages: LanguagePair(source: source, target: target),
            model: values["model"] ?? Self.default.model
        )
    }

    /// `$XDG_CONFIG_HOME/mynah/config.conf`, else `~/.config/mynah/config.conf`.
    ///
    /// The variable is honoured only when it is an **absolute** path, per the XDG
    /// base directory spec — a relative value is invalid, and resolving it against
    /// the current directory would point the app at its own empty scratch dir
    /// (Finding: gui-claude-subprocess-tcc-prompt).
    ///
    /// Environment and home come in as parameters so tests never read the
    /// developer's real `$HOME`.
    public static func path(environment: [String: String], home: URL) -> URL {
        if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            return URL(fileURLWithPath: xdg).appendingPathComponent("mynah/config.conf")
        }
        return home.appendingPathComponent(".config/mynah/config.conf")
    }

    /// Read and parse the config, or return `.default` when there is no file.
    ///
    /// "Absent" is a deliberate state — every fresh `brew install` is in it.
    /// "Present but unreadable" is a problem the user wants told about, so it
    /// throws rather than falling back.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) throws -> MynahConfig {
        let url = path(environment: environment, home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return .default }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError(
                path: url.path,
                line: nil,
                reason: "could not be read (\(error.localizedDescription))"
            )
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigError(path: url.path, line: nil, reason: "is not valid UTF-8")
        }
        return try parse(text, path: url.path)
    }

    /// Drop one matched pair of surrounding double quotes. Without this,
    /// `target = "German"` yields a language literally named `"German"`, which the
    /// model would probably still translate into — so the mistake would be
    /// invisible rather than wrong.
    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }
}

/// A config file that exists but cannot be used, phrased so both products can
/// print it unchanged: the CLI to stderr, the app into the translation panel.
public struct ConfigError: Error, CustomStringConvertible, Equatable {
    public let path: String
    /// nil when the problem is the file as a whole rather than one line.
    public let line: Int?
    public let reason: String

    public init(path: String, line: Int?, reason: String) {
        self.path = path
        self.line = line
        self.reason = reason
    }

    public var description: String {
        guard let line else { return "\(path): \(reason)" }
        return "\(path) line \(line): \(reason)"
    }
}
