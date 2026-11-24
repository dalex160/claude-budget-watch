import XCTest
@testable import BudgetGuardCore

final class UsageParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func usage(_ sevenDay: String) -> Data {
        Data("{\"five_hour\":null,\"seven_day\":\(sevenDay)}".utf8)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPicksFirstChatOrganization() throws {
        XCTAssertEqual(try UsageParser.organizationID(fromOrganizationsJSON: fixture("orgs-two")), "org-chat")
    }

    func testFallsBackToFirstOrganizationWithoutChat() throws {
        let data = Data(#"[{"uuid":"a","capabilities":[]},{"uuid":"b"}]"#.utf8)
        XCTAssertEqual(try UsageParser.organizationID(fromOrganizationsJSON: data), "a")
    }

    func testEmptyOrganizationsThrows() {
        XCTAssertThrowsError(try UsageParser.organizationID(fromOrganizationsJSON: Data("[]".utf8))) {
            XCTAssertEqual($0 as? UsageParseError, .noOrganization)
        }
    }

    func testParsesMaxUsage() throws {
        let s = try UsageParser.snapshot(fromUsageJSON: fixture("usage-max"), now: now)
        XCTAssertEqual(s.weeklyPercent, 29)
        let expected = try XCTUnwrap(ISO8601DateFormatter.fractional.date(from: "2026-11-28T12:59:59.931Z"))
        XCTAssertEqual(try XCTUnwrap(s.resetsAt).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(s.extraUsage, ExtraUsage(isEnabled: false, disabledReason: "out_of_credits"))
        XCTAssertEqual(s.fetchedAt, now)
    }

    func testFractionalUtilizationIsRounded() throws {
        let s = try UsageParser.snapshot(fromUsageJSON: usage(#"{"utilization":29.6}"#), now: now)
        XCTAssertEqual(s.weeklyPercent, 30)
    }

    func testUtilizationClampedTo100() throws {
        XCTAssertEqual(try UsageParser.snapshot(fromUsageJSON: usage(#"{"utilization":104.2}"#), now: now).weeklyPercent, 100)
        XCTAssertEqual(try UsageParser.snapshot(fromUsageJSON: usage(#"{"utilization":-1}"#), now: now).weeklyPercent, 0)
    }

    func testFreeAccountThrowsNoWeeklyLimit() throws {
        let data = try fixture("usage-free")
        XCTAssertThrowsError(try UsageParser.snapshot(fromUsageJSON: data, now: now)) {
            XCTAssertEqual($0 as? UsageParseError, .noWeeklyLimit)
        }
    }

    func testGarbageThrowsMalformed() {
        let data = Data("<html>Just a moment</html>".utf8)
        XCTAssertThrowsError(try UsageParser.snapshot(fromUsageJSON: data, now: now)) {
            XCTAssertEqual($0 as? UsageParseError, .malformed)
        }
    }

    func testMissingResetsAtGivesNil() throws {
        let s = try UsageParser.snapshot(fromUsageJSON: usage(#"{"utilization":10}"#), now: now)
        XCTAssertNil(s.resetsAt)
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
