import Foundation

/// A cancellation handle for work already in flight.
///
/// Deliberately says nothing about *how* the work is cancelled. `TextTranslator`
/// is the documented backend-swap point (Decision 0006): today the backend is a
/// `claude` subprocess and cancelling means terminating it, but a litellm or HTTP
/// backend would cancel a request instead. A protocol that handed out a
/// `Foundation.Process` could not be implemented by such a backend at all.
///
/// `cancel()` is idempotent: the panel can be dismissed twice in quick succession
/// (Esc, then focus loss as the app hides), and terminating a reaped process twice
/// is not something callers should have to guard against.
///
/// Deliberately a hand-locked class rather than an `actor`: `cancel()` is called
/// from the main actor while the translation runs on a background task, so an
/// `actor` would make it `async` and push every call site into a `Task`. That
/// indirection is what made cancellation unreliable in the first place — the panel
/// must be able to kill the call synchronously as it closes. Do not "simplify"
/// this into an actor.
public final class TranslationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?

    public init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        lock.lock()
        let action = onCancel
        onCancel = nil
        lock.unlock()
        action?()
    }
}
