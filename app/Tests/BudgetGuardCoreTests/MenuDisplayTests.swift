import XCTest
@testable import BudgetGuardCore

final class MenuDisplayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let cal = Calendar(identifier: .gregorian)

    private func snap(_ p: Int) -> UsageSnapshot {
        UsageSnapshot(weeklyPercent: p, resetsAt: nil, extraUsage: nil, fetchedAt: now)
    }

    func testLoadingBeforeFirstFetch() {
        let d = makeMenuDisplay(snapshot: nil, error: nil, now: now, calendar: cal)
        XCTAssertEqual(d.title, "—")
        XCTAssertEqual(d.tone, .neutral)
        XCTAssertEqual(d.lines, ["Chargement…"])
        XCTAssertFalse(d.showsReconnect)
    }

    func testFreshSnapshotToneFollowsLevel() {
        XCTAssertEqual(makeMenuDisplay(snapshot: snap(10), error: nil, now: now, calendar: cal).tone, .normal)
        XCTAssertEqual(makeMenuDisplay(snapshot: snap(75), error: nil, now: now, calendar: cal).tone, .warning)
        XCTAssertEqual(makeMenuDisplay(snapshot: snap(95), error: nil, now: now, calendar: cal).tone, .critical)
    }

    func testStaleSnapshotIsGrey() {
        let d = makeMenuDisplay(snapshot: snap(95), error: .network, now: now, calendar: cal)
        XCTAssertEqual(d.tone, .stale)
        XCTAssertEqual(d.title, "95\u{202F}%")
    }

    func testNotLoggedInIsNeutralWithReconnect() {
        let d = makeMenuDisplay(snapshot: nil, error: .notLoggedIn, now: now, calendar: cal)
        XCTAssertEqual(d.tone, .neutral)
        XCTAssertTrue(d.showsReconnect)
        XCTAssertEqual(d.title, "—")
    }

    func testRateLimitedIsCritical() {
        XCTAssertEqual(makeMenuDisplay(snapshot: nil, error: .rateLimited, now: now, calendar: cal).tone, .critical)
    }

    func testAlertPercent() {
        XCTAssertEqual(alertPercent(snapshot: snap(82), error: nil), 82)
        XCTAssertEqual(alertPercent(snapshot: nil, error: .rateLimited), 100)
        XCTAssertEqual(alertPercent(snapshot: snap(50), error: .rateLimited), 100)
        XCTAssertNil(alertPercent(snapshot: snap(82), error: .network))
        XCTAssertNil(alertPercent(snapshot: nil, error: .notLoggedIn))
        XCTAssertNil(alertPercent(snapshot: nil, error: nil))
    }
}
