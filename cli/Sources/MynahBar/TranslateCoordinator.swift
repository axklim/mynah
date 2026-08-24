import AppKit
import Foundation
import MynahCore
import MynahUI

/// Orchestrates one translation: guards against overlap, reads the clipboard,
/// runs the translator off the main actor, and drives the floating panel.
///
/// Has its **own** in-flight guard rather than sharing the checker's: they are
/// separate UIs, and a translation refusing because a check happened to be running
/// would just be puzzling. Two `claude` subprocesses at once is fine.
@MainActor
final class TranslateCoordinator {
    private let status: StatusItemController
    /// Built fresh for every run rather than stored, so the config file is re-read
    /// on each press: edit it, press the hotkey, done — no restart, no "Reload
    /// config" menu item. A throwing closure also gives a broken config somewhere
    /// to land (the panel) instead of crashing the app at launch.
    private let makeTranslator: () throws -> any TextTranslator
    private let panel: TranslationPanel

    private var isTranslating = false
    private var handle: TranslationHandle?

    /// Bumped on every run. A reply from run *n* is dropped once run *n + 1* has
    /// started, so a slow translation cannot paint over a newer one — or over a
    /// panel the user has already dismissed and reopened.
    private var generation = 0

    init(status: StatusItemController, makeTranslator: @escaping () throws -> any TextTranslator) {
        self.status = status
        self.makeTranslator = makeTranslator
        var dismissed: (() -> Void)?
        self.panel = TranslationPanel(
            onDismiss: { dismissed?() },
            focusGraceSeconds: {
                (try? MynahConfig.load())?.translationFocusGraceSeconds
                    ?? MynahConfig.default.translationFocusGraceSeconds
            }
        )
        dismissed = { [weak self] in self?.handleDismissal() }
    }

    func runTranslate() {
        // Ignore re-triggers while a translation is in flight, matching the checker.
        // Pressing the hotkey while the panel is merely open starts a fresh one.
        guard !isTranslating else { return }

        let source: String
        switch InputText.check(clipboardText()) {
        case .ok(let trimmed):
            source = trimmed
        case let rejected:
            // Rejections are reported in the window, never in the icon: the panel is
            // this feature's UI, and a blinking icon with no window explains nothing.
            if let state = TranslationViewState.rejection(rejected) {
                panel.show(state)
            }
            return
        }

        // After the input guard, not before: an empty clipboard is the common
        // mistake and deserves the plainer message. (The CLI loads first only
        // because its input can block on stdin.)
        let translator: any TextTranslator
        do {
            translator = try makeTranslator()
        } catch {
            panel.show(TranslationViewState.configFailure(error))
            return
        }

        generation += 1
        let run = generation
        isTranslating = true
        status.show(.translating)
        panel.show(.loading)

        Task {
            let state = await Self.translate(translator, source) { [weak self] handle in
                Task { @MainActor in self?.adopt(handle, for: run) }
            }
            guard self.generation == run else { return }   // a newer run owns the panel
            self.isTranslating = false
            self.handle = nil
            self.status.show(.neutral)
            self.panel.update(state)
        }
    }

    /// Keep the handle only while it belongs to the current, still-running translation.
    ///
    /// Two distinct races make both halves of the guard load-bearing:
    /// - `generation != run` means the user dismissed and started something else, so
    ///   this handle belongs to a run nobody is waiting for.
    /// - `!isTranslating` means *this very run* already finished — its completion
    ///   continuation beat the `adopt` hop to the main actor. The generation still
    ///   matches, so `generation` alone would not catch it, and storing the handle
    ///   would leave a dead run's process recorded as live.
    ///
    /// In both cases the handle is cancelled immediately rather than stored, so no
    /// subprocess outlives the window that wanted it. Do not drop either condition.
    private func adopt(_ handle: TranslationHandle, for run: Int) {
        guard generation == run, isTranslating else {
            handle.cancel()
            return
        }
        self.handle = handle
    }

    /// Esc or focus loss: kill the call, drop the icon back to neutral, and make
    /// sure a late reply has nothing to paint into.
    private func handleDismissal() {
        handle?.cancel()
        handle = nil
        if isTranslating {
            isTranslating = false
            generation += 1      // invalidate the in-flight run
            status.show(.neutral)
        }
    }

    /// Run the (blocking) translator off the main actor and map it to a view state.
    private static func translate(
        _ translator: any TextTranslator,
        _ source: String,
        onStart: @escaping @Sendable (TranslationHandle) -> Void
    ) async -> TranslationViewState {
        await Task.detached(priority: .userInitiated) {
            do {
                let result = try translator.translate(source, onStart: onStart)
                return TranslationViewState.from(result, source: source)
            } catch {
                FileHandle.standardError.write(Data("mynah-bar: \(error)\n".utf8))
                return TranslationViewState.failure(error)
            }
        }.value
    }
}
