import AppKit
import Foundation
import SpellCheckerCore

/// Orchestrates one check: guards against overlap, reads the clipboard, runs the
/// evaluator off the main thread, and maps the outcome to an `IconState`.
@MainActor
final class CheckCoordinator {
    private let status: StatusItemController
    private let evaluator: any TextEvaluator
    private var isChecking = false

    init(status: StatusItemController, evaluator: any TextEvaluator) {
        self.status = status
        self.evaluator = evaluator
    }

    func runCheck() {
        // Ignore re-triggers while a check is in flight — no overlapping runs.
        guard !isChecking else { return }

        let text = (NSPasteboard.general.string(forType: .string) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status.show(.empty)  // nothing to check — not an error
            return
        }

        isChecking = true
        status.show(.working)
        let evaluator = self.evaluator
        Task {
            let state = await Self.evaluate(evaluator, text)
            self.isChecking = false
            self.status.show(state)
        }
    }

    /// Run the (blocking) evaluator off the main actor and map to an IconState.
    private static func evaluate(_ evaluator: any TextEvaluator, _ text: String) async -> IconState {
        await Task.detached(priority: .userInitiated) {
            do {
                return IconState.verdict(try evaluator.evaluate(text))
            } catch {
                FileHandle.standardError.write(Data("spell-checker-bar: \(error)\n".utf8))
                return IconState.error
            }
        }.value
    }
}
