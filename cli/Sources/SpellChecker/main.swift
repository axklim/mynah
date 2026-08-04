import Foundation
import SpellCheckerCore

let usage = """
spell-checker — evaluate whether a message reads clearly.

USAGE:
  spell-checker check <text>     Evaluate text; prints one verdict: 🔴 / 🟡 / 🟢
  spell-checker check            Read the text from stdin (e.g. pbpaste | spell-checker check)
  spell-checker --help           Show this help

Input over 2000 characters is rejected as a likely misclick.
"""

func emit(_ text: String, to handle: FileHandle) {
    handle.write(Data((text + "\n").utf8))
}

func fail(_ message: String, code: Int32) -> Never {
    emit(message, to: .standardError)
    exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "-h", "--help", "help":
    emit(usage, to: .standardOutput)

case "check":
    let rest = Array(args.dropFirst())
    let raw = rest.isEmpty
        ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        : rest.joined(separator: " ")

    let text: String
    switch InputText.check(raw) {
    case .ok(let trimmed):
        text = trimmed
    case .noText:
        fail("usage: spell-checker check <text>   (or pipe text via stdin)", code: 2)
    case .tooLong(let count):
        fail(
            """
            error: input is \(count) characters, limit is \(InputText.characterLimit)
            That looks like an accidental paste — check what you copied.
            """,
            code: 2
        )
    }

    let evaluator: TextEvaluator = ClaudeCLIEvaluator()
    do {
        emit(try evaluator.evaluate(text).display, to: .standardOutput)
    } catch {
        fail("error: \(error)", code: 1)
    }

case .none:
    fail(usage, code: 2)

default:
    fail("unknown command: \(args.first!)\n\n" + usage, code: 2)
}
