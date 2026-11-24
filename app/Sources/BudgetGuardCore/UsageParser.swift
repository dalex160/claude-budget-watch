import Foundation

public enum UsageParser {
    public static func organizationID(fromOrganizationsJSON data: Data) throws -> String {
        guard let orgs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw UsageParseError.malformed
        }
        let chat = orgs.first { ($0["capabilities"] as? [String])?.contains("chat") == true }
        guard let org = chat ?? orgs.first else { throw UsageParseError.noOrganization }
        guard let uuid = org["uuid"] as? String else { throw UsageParseError.malformed }
        return uuid
    }

    public static func snapshot(fromUsageJSON data: Data, now: Date) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageParseError.malformed
        }
        guard let weekly = root["seven_day"] as? [String: Any] else {
            throw UsageParseError.noWeeklyLimit
        }
        guard let utilization = (weekly["utilization"] as? NSNumber)?.doubleValue else {
            throw UsageParseError.malformed
        }
        let percent = Int(min(100, max(0, utilization)).rounded())
        let resetsAt = (weekly["resets_at"] as? String).flatMap(parseDate)

        var extra: ExtraUsage?
        if let e = root["extra_usage"] as? [String: Any], let enabled = e["is_enabled"] as? Bool {
            extra = ExtraUsage(isEnabled: enabled, disabledReason: e["disabled_reason"] as? String)
        }
        return UsageSnapshot(weeklyPercent: percent, resetsAt: resetsAt, extraUsage: extra, fetchedAt: now)
    }

    private static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
