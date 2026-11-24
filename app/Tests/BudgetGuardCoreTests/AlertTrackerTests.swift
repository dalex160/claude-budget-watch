import XCTest
@testable import BudgetGuardCore

private final class MemoryStore: AlertStateStore {
    var flags: [Int: Bool] = [:]
    func isNotified(_ threshold: Int) -> Bool { flags[threshold] ?? false }
    func setNotified(_ threshold: Int, _ value: Bool) { flags[threshold] = value }
}

final class AlertTrackerTests: XCTestCase {
    private var suiteName: String!

    override func tearDown() {
        if let suiteName { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        super.tearDown()
    }

    func testBelowAllNoAlert() {
        let t = AlertTracker(store: MemoryStore())
        XCTAssertEqual(t.thresholdsToAlert(for: 50), [])
    }

    func testCross80Once() {
        let t = AlertTracker(store: MemoryStore())
        XCTAssertEqual(t.thresholdsToAlert(for: 82), [80])
        XCTAssertEqual(t.thresholdsToAlert(for: 85), [])
    }

    func testRearmAfterDrop() {
        let t = AlertTracker(store: MemoryStore())
        XCTAssertEqual(t.thresholdsToAlert(for: 82), [80])
        XCTAssertEqual(t.thresholdsToAlert(for: 40), [])
        XCTAssertEqual(t.thresholdsToAlert(for: 81), [80])
    }

    func testJumpStraightTo100SendsBothAlertsOnce() {
        let t = AlertTracker(store: MemoryStore())
        XCTAssertEqual(t.thresholdsToAlert(for: 100), [80, 95])
        XCTAssertEqual(t.thresholdsToAlert(for: 100), [])
    }

    func testPersistsAcrossInstances() {
        suiteName = "test.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        XCTAssertEqual(AlertTracker(store: UserDefaultsAlertStateStore(defaults: defaults)).thresholdsToAlert(for: 82), [80])
        let second = AlertTracker(store: UserDefaultsAlertStateStore(defaults: defaults))
        XCTAssertEqual(second.thresholdsToAlert(for: 83), [])
    }
}
