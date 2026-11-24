import Foundation

public struct ExtraUsage: Equatable, Codable {
    public let isEnabled: Bool
    public let disabledReason: String?

    public init(isEnabled: Bool, disabledReason: String?) {
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

public struct UsageSnapshot: Equatable, Codable {
    public let weeklyPercent: Int
    public let resetsAt: Date?
    public let extraUsage: ExtraUsage?
    public let fetchedAt: Date

    public init(weeklyPercent: Int, resetsAt: Date?, extraUsage: ExtraUsage?, fetchedAt: Date) {
        self.weeklyPercent = weeklyPercent
        self.resetsAt = resetsAt
        self.extraUsage = extraUsage
        self.fetchedAt = fetchedAt
    }
}

public enum UsageParseError: Error, Equatable {
    case malformed, noWeeklyLimit, noOrganization
}
