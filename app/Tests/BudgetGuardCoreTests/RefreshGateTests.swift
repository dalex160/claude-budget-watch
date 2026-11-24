import XCTest
@testable import BudgetGuardCore

final class RefreshGateTests: XCTestCase {
    func testFirstRequestStarts() {
        var g = RefreshGate()
        XCTAssertNotNil(g.request())
    }

    func testNoOverlappingFetches() {
        var g = RefreshGate()
        XCTAssertNotNil(g.request())
        XCTAssertNil(g.request())
    }

    func testRerunAfterInFlightFetch() {
        var g = RefreshGate()
        let t = g.request()!
        XCTAssertNil(g.request())
        let o = g.complete(t)
        XCTAssertTrue(o.accept)
        XCTAssertTrue(o.rerun)
        XCTAssertNotNil(g.request())
    }

    func testNoRerunWithoutPendingRequest() {
        var g = RefreshGate()
        let t = g.request()!
        XCTAssertFalse(g.complete(t).rerun)
    }

    func testStaleResultDroppedAfterReset() {
        var g = RefreshGate()
        let t = g.request()!
        g.reset()
        XCTAssertNil(g.request())            // coalesced: queued behind the old fetch
        let o = g.complete(t)
        XCTAssertFalse(o.accept)             // old source's result must not be shown
        XCTAssertTrue(o.rerun)               // but the refresh for the new source runs
        let t2 = g.request()!
        XCTAssertTrue(g.complete(t2).accept)
    }
}
