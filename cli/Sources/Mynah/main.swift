import Foundation
import MynahCore

let usage = """
mynah — evaluate whether a message reads clearly.

USAGE:
  mynah check <text>       Evaluate text; prints one verdict: 🔴 / 🟡 / 🟢
  mynah check              Read the text from stdin (e.g. pbpaste | mynah check)
  mynah translate <text>   Translate English → Russian
  mynah translate          Read the text from stdin
  mynah --help             Show this help
  mynah --version          Print the version

Input over 2000 characters is rejected as a likely misclick.
"""

func emit(_ text: String, to handle: FileHandle) {
    handle.write(Data((text + "\n").utf8))
}

func fail(_ message: String, code: Int32) -> Never {
    emit(message, to: .standardError)
    exit(code)
}

/// Read a subcommand's text from arguments or stdin, then apply the shared input
/// rule. Both subcommands must reject identically; keeping two copies of this is
/// how they silently diverge when the limit or the wording changes.
func requireInput(_ rest: [String], usage hint: String) -> String {
    let raw = rest.isEmpty
        ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        : rest.joined(separator: " ")

    switch InputText.check(raw) {
    case .ok(let trimmed):
        return trimmed
    case .noText:
        fail(hint, code: 2)
    case .tooLong(let count):
        fail(
            """
            error: input is \(count) characters, limit is \(InputText.characterLimit)
            That looks like an accidental paste — check what you copied.
            """,
            code: 2
        )
    }
}

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "-h", "--help", "help":
    emit(usage, to: .standardOutput)

case "--version", "version":
    emit(MynahVersion.current, to: .standardOutput)

case "check":
    let text = requireInput(
        Array(args.dropFirst()),
        usage: "usage: mynah check <text>   (or pipe text via stdin)"
    )

    let evaluator: TextEvaluator = ClaudeCLIEvaluator()
    do {
        emit(try evaluator.evaluate(text).display, to: .standardOutput)
    } catch {
        fail("error: \(error)", code: 1)
    }

case "translate":
    let source = requireInput(
        Array(args.dropFirst()),
        usage: "usage: mynah translate <text>   (or pipe text via stdin)"
    )

    let translator: TextTranslator = ClaudeCLITranslator()
    do {
        emit(try translator.translate(source).terminalText(source: source), to: .standardOutput)
    } catch {
        fail("error: \(error)", code: 1)
    }

case .none:
    fail(usage, code: 2)

default:
    fail("unknown command: \(args.first!)\n\n" + usage, code: 2)
}
