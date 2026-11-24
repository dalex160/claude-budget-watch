import Foundation

public enum Copy {
    static let narrowSpace = "\u{202F}"

    public static let loading = "Chargement…"

    public static func percentTitle(_ percent: Int?) -> String {
        guard let percent else { return "—" }
        return "\(percent)\(narrowSpace)%"
    }

    /// "14 h" or "14 h 30", read in the calendar's time zone.
    public static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hour = c.hour ?? 0
        let minute = c.minute ?? 0
        return minute == 0 ? "\(hour) h" : "\(hour) h " + String(format: "%02d", minute)
    }

    public static func resetLine(_ date: Date, now: Date, calendar: Calendar) -> String {
        let rounded = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let day: String
        if calendar.isDate(rounded, inSameDayAs: now) {
            day = "aujourd’hui"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(rounded, inSameDayAs: tomorrow) {
            day = "demain"
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.dateFormat = "EEEE"
            day = f.string(from: rounded).lowercased()
        }
        return "Remise à zéro \(day) à \(clock(rounded, calendar: calendar))"
    }

    public static func extraUsageLine(_ extra: ExtraUsage?) -> String? {
        guard let extra else { return nil }
        return "Dépassement du forfait : " + (extra.isEnabled ? "activé" : "désactivé")
    }

    public static func alertBody(threshold: Int, percent: Int) -> String {
        "Vous avez utilisé \(percent)\(narrowSpace)% de votre limite de la semaine."
    }

    public static func usageSentence(_ percent: Int) -> String {
        "Vous avez utilisé \(percent)\(narrowSpace)% de votre limite de la semaine"
    }

    static let notLoggedIn = "Vous n’êtes plus connecté à Claude."
    public static let unsupportedPlan = "Budget Guard fonctionne avec les abonnements Claude Pro et Max."

    static func staleLine(_ fetchedAt: Date, calendar: Calendar) -> String {
        "Dernière mise à jour à \(clock(fetchedAt, calendar: calendar)) — connexion impossible"
    }
}
