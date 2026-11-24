import Foundation

public struct MenuModel: Equatable {
    public let title: String
    public let level: UsageLevel?
    public let isStale: Bool
    public let lines: [String]
    public let showsReconnect: Bool

    public init(title: String, level: UsageLevel?, isStale: Bool, lines: [String], showsReconnect: Bool) {
        self.title = title
        self.level = level
        self.isStale = isStale
        self.lines = lines
        self.showsReconnect = showsReconnect
    }
}

public func makeMenuModel(snapshot: UsageSnapshot?, error: UsageFetchError?, now: Date, calendar: Calendar) -> MenuModel {
    switch error {
    case .notLoggedIn:
        return MenuModel(title: Copy.percentTitle(nil), level: nil, isStale: false,
                         lines: [Copy.notLoggedIn], showsReconnect: true)
    case .unsupportedPlan:
        return MenuModel(title: Copy.percentTitle(nil), level: nil, isStale: false,
                         lines: [Copy.unsupportedPlan], showsReconnect: false)
    case .rateLimited:
        return MenuModel(title: Copy.percentTitle(100), level: .critical, isStale: false,
                         lines: [Copy.usageSentence(100)], showsReconnect: false)
    case .network, .cloudflare, .malformed, nil:
        break
    }

    guard let snapshot else {
        return MenuModel(title: Copy.percentTitle(nil), level: nil, isStale: true,
                         lines: error == nil ? [] : [Copy.unavailable], showsReconnect: false)
    }

    var lines = [Copy.usageSentence(snapshot.weeklyPercent)]
    if let resetsAt = snapshot.resetsAt {
        lines.append(Copy.resetLine(resetsAt, now: now, calendar: calendar))
    }
    if let extra = Copy.extraUsageLine(snapshot.extraUsage) {
        lines.append(extra)
    }
    let stale = error != nil
    if stale {
        lines.append(Copy.staleLine(snapshot.fetchedAt, calendar: calendar))
    }
    return MenuModel(title: Copy.percentTitle(snapshot.weeklyPercent),
                     level: UsageLevel(percent: snapshot.weeklyPercent),
                     isStale: stale, lines: lines, showsReconnect: false)
}
