import XCTest
@testable import BudgetGuardCore

final class CopyTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.locale = Locale(identifier: "fr_FR")
        return c
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        return ISO8601DateFormatter().date(from: iso)!
    }

    func testPercentTitle() {
        XCTAssertEqual(Copy.percentTitle(29), "29\u{202F}%")
        XCTAssertEqual(Copy.percentTitle(nil), "—")
    }

    func testResetLineOtherDay() {
        let line = Copy.resetLine(date("2026-11-27T12:59:59.93Z"), now: date("2026-11-24T10:00:00Z"), calendar: calendar)
        XCTAssertEqual(line, "Remise à zéro vendredi à 14 h")
    }

    func testResetLineTomorrowWithMinutes() {
        let line = Copy.resetLine(date("2026-11-25T13:30:00Z"), now: date("2026-11-24T10:00:00Z"), calendar: calendar)
        XCTAssertEqual(line, "Remise à zéro demain à 14 h 30")
    }

    func testResetLineToday() {
        let line = Copy.resetLine(date("2026-11-24T16:00:00Z"), now: date("2026-11-24T10:00:00Z"), calendar: calendar)
        XCTAssertEqual(line, "Remise à zéro aujourd’hui à 17 h")
    }

    func testExtraUsageLines() {
        XCTAssertEqual(Copy.extraUsageLine(ExtraUsage(isEnabled: true, disabledReason: nil)), "Dépassement du forfait : activé")
        XCTAssertEqual(Copy.extraUsageLine(ExtraUsage(isEnabled: false, disabledReason: nil)), "Dépassement du forfait : désactivé")
        XCTAssertNil(Copy.extraUsageLine(nil))
    }

    func testAlertBody() {
        XCTAssertEqual(Copy.alertBody(threshold: 80, percent: 82), "Vous avez utilisé 82\u{202F}% de votre limite de la semaine.")
    }

    func testLevels() {
        XCTAssertEqual(UsageLevel(percent: 69), .normal)
        XCTAssertEqual(UsageLevel(percent: 70), .warning)
        XCTAssertEqual(UsageLevel(percent: 89), .warning)
        XCTAssertEqual(UsageLevel(percent: 90), .critical)
    }
}
