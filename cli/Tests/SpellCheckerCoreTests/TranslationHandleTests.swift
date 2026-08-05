import Foundation
import XCTest
@testable import SpellCheckerCore

final class TranslationHandleTests: XCTestCase {
    func testCancelRunsTheAction() {
        // `nonisolated(unsafe)`: this var is only ever touched synchronously,
        // within this function body — the closure never actually escapes to
        // another thread here — but the compiler can't see that through the
        // `@Sendable` parameter type, so it flags the mutable capture as a
        // potential data race under Swift 6 strict concurrency.
        nonisolated(unsafe) var cancelled = false
        let handle = TranslationHandle { cancelled = true }
        handle.cancel()
        XCTAssertTrue(cancelled)
    }

    func testCancelIsIdempotent() {
        // The panel can be dismissed twice (Esc, then focus loss as the app hides),
        // and terminating an already-reaped process must not be attempted twice.
        nonisolated(unsafe) var count = 0
        let handle = TranslationHandle { count += 1 }
        handle.cancel()
        handle.cancel()
        handle.cancel()
        XCTAssertEqual(count, 1)
    }

    func testNotCancellingRunsNothing() {
        nonisolated(unsafe) var cancelled = false
        _ = TranslationHandle { cancelled = true }
        XCTAssertFalse(cancelled)
    }

    func testCancelIsThreadSafeUnderConcurrentCalls() {
        // The NSLock exists for exactly this: Esc arriving on the main actor can race
        // the panel losing key status. Sequential idempotency (above) does not prove it.
        //
        // A locked counter here rather than `nonisolated(unsafe)` — unlike the other
        // tests, this var really is written from several threads, so the unsafe opt-out
        // would be papering over a genuine race instead of a conservative check.
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func bump() { lock.lock(); value += 1; lock.unlock() }
            var current: Int { lock.lock(); defer { lock.unlock() }; return value }
        }

        let counter = Counter()
        let handle = TranslationHandle { counter.bump() }
        DispatchQueue.concurrentPerform(iterations: 64) { _ in handle.cancel() }
        XCTAssertEqual(counter.current, 1, "cancel must collapse to one action under concurrency")
    }
}
