import AppKit
import Foundation
import MynahCore

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

        let text: String
        switch InputText.check(clipboardText()) {
        case .ok(let trimmed):
            text = trimmed
        case .noText:
            status.show(.empty)    // nothing to check — not an error
            return
        case .tooLong:
            status.show(.tooLong)  // a whole page got copied; don't spend a call on it
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
                FileHandle.standardError.write(Data("mynah-bar: \(error)\n".utf8))
                return IconState.error
            }
        }.value
    }
}
