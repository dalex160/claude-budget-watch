import XCTest
@testable import BudgetGuardCore

final class MenuModelTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.locale = Locale(identifier: "fr_FR")
        return c
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private var now: Date { date("2026-11-24T10:00:00Z") }

    private var snapshot: UsageSnapshot {
        UsageSnapshot(weeklyPercent: 29,
                      resetsAt: date("2026-11-25T13:30:00Z"),
                      extraUsage: ExtraUsage(isEnabled: false, disabledReason: nil),
                      fetchedAt: date("2026-11-24T09:02:00Z"))
    }

    func testMenuModelFresh() {
        let m = makeMenuModel(snapshot: snapshot, error: nil, now: now, calendar: calendar)
        XCTAssertEqual(m.title, "29\u{202F}%")
        XCTAssertEqual(m.level, .normal)
        XCTAssertFalse(m.isStale)
        XCTAssertEqual(m.lines, [
            "Vous avez utilisé 29\u{202F}% de votre limite de la semaine",
            "Remise à zéro demain à 14 h 30",
            "Dépassement du forfait : désactivé",
        ])
        XCTAssertFalse(m.showsReconnect)
    }

    func testMenuModelKeepsLastValueGreyedOnNetworkError() {
        for error in [UsageFetchError.network, .cloudflare, .malformed] {
            let m = makeMenuModel(snapshot: snapshot, error: error, now: now, calendar: calendar)
            XCTAssertEqual(m.title, "29\u{202F}%")
            XCTAssertTrue(m.isStale)
            XCTAssertEqual(m.lines.last, "Dernière mise à jour à 10 h 02 — connexion impossible")
        }
    }

    func testMenuModelNotLoggedIn() {
        let m = makeMenuModel(snapshot: snapshot, error: .notLoggedIn, now: now, calendar: calendar)
        XCTAssertEqual(m.title, "—")
        XCTAssertNil(m.level)
        XCTAssertTrue(m.showsReconnect)
        XCTAssertEqual(m.lines, ["Vous n’êtes plus connecté à Claude."])
    }

    func testMenuModelRateLimited() {
        let m = makeMenuModel(snapshot: nil, error: .rateLimited, now: now, calendar: calendar)
        XCTAssertEqual(m.title, "100\u{202F}%")
        XCTAssertEqual(m.level, .critical)
        let withSnap = makeMenuModel(snapshot: snapshot, error: .rateLimited, now: now, calendar: calendar)
        XCTAssertEqual(withSnap.title, "100\u{202F}%")
        XCTAssertEqual(withSnap.level, .critical)
    }

    func testMenuModelUnsupportedPlan() {
        let m = makeMenuModel(snapshot: nil, error: .unsupportedPlan, now: now, calendar: calendar)
        XCTAssertEqual(m.title, "—")
        XCTAssertNil(m.level)
        XCTAssertFalse(m.showsReconnect)
        XCTAssertEqual(m.lines, ["Budget Guard fonctionne avec les abonnements Claude Pro et Max."])
    }

    func testErrorBeforeFirstReadingShowsUnavailableLine() {
        for e in [UsageFetchError.network, .cloudflare, .malformed] {
            let m = makeMenuModel(snapshot: nil, error: e, now: now, calendar: calendar)
            XCTAssertEqual(m.lines, ["Connexion impossible pour le moment"])
            XCTAssertTrue(m.isStale)
            XCTAssertEqual(m.title, "—")
            XCTAssertFalse(m.showsReconnect)
        }
    }
}
