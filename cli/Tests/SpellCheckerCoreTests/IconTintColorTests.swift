import AppKit
import XCTest
@testable import SpellCheckerCore
@testable import SpellCheckerUI

/// Guards the `IconTint -> NSColor` mapping directly, and — more importantly —
/// through the full `IconState -> IconTint -> NSColor` chain a verdict actually
/// travels. A test that only checked the last hop would stay green even if
/// `IconState.tint` got a case reordered under it (e.g. `.green` silently
/// mapped to `.red`'s tint); see the Finding this guards against.
final class IconTintColorTests: XCTestCase {
    func testMappingByIdentity() {
        XCTAssertEqual(nsColor(for: .green), .systemGreen)
        XCTAssertEqual(nsColor(for: .yellow), .systemYellow)
        XCTAssertEqual(nsColor(for: .red), .systemRed)
        XCTAssertEqual(nsColor(for: .orange), .systemOrange)
        XCTAssertEqual(nsColor(for: .standard), .labelColor)
    }

    func testVerdictColorReachedThroughTheFullChain() {
        XCTAssertEqual(nsColor(for: IconState.verdict(.green).tint), .systemGreen)
        XCTAssertEqual(nsColor(for: IconState.verdict(.yellow).tint), .systemYellow)
        XCTAssertEqual(nsColor(for: IconState.verdict(.red).tint), .systemRed)
    }
}
