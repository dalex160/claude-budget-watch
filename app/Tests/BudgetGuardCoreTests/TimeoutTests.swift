import XCTest
@testable import BudgetGuardCore

final class TimeoutTests: XCTestCase {
    func testReturnsResultWhenOperationIsFast() async throws {
        let v = try await withTimeout(seconds: 5) { 42 }
        XCTAssertEqual(v, 42)
    }

    func testThrowsNetworkWhenOperationHangs() async {
        let start = Date()
        do {
            // Ignores cancellation on purpose: a dead web process never answers either.
            _ = try await withTimeout(seconds: 0.2) { () async throws -> Int in
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                return 1
            }
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? UsageFetchError, .network)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testPropagatesOperationError() async {
        do {
            _ = try await withTimeout(seconds: 5) { () async throws -> Int in throw UsageFetchError.notLoggedIn }
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? UsageFetchError, .notLoggedIn)
        }
    }
}
