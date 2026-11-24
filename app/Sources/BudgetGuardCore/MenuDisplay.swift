import Foundation

/// What colour the menu bar value takes. `neutral` = system label colour.
public enum DisplayTone: Equatable {
    case neutral, normal, warning, critical, stale
}

public struct MenuDisplay: Equatable {
    public let title: String
    public let tone: DisplayTone
    public let lines: [String]
    public let showsReconnect: Bool
}

/// App-layer view of `makeMenuModel`: handles the "before the first fetch" case and maps level/staleness to a tone.
public func makeMenuDisplay(snapshot: UsageSnapshot?, error: UsageFetchError?, now: Date, calendar: Calendar) -> MenuDisplay {
    if snapshot == nil && error == nil {
        return MenuDisplay(title: Copy.percentTitle(nil), tone: .neutral, lines: [Copy.loading], showsReconnect: false)
    }
    let model = makeMenuModel(snapshot: snapshot, error: error, now: now, calendar: calendar)
    let tone: DisplayTone
    if model.isStale {
        tone = .stale
    } else {
        switch model.level {
        case .normal?: tone = .normal
        case .warning?: tone = .warning
        case .critical?: tone = .critical
        case nil: tone = .neutral
        }
    }
    return MenuDisplay(title: model.title, tone: tone, lines: model.lines, showsReconnect: model.showsReconnect)
}

/// Percentage to feed the alert tracker for a refresh result; nil = do not touch alert state.
/// A rate-limited account counts as 100 %; a stale (failed) refresh never alerts.
public func alertPercent(snapshot: UsageSnapshot?, error: UsageFetchError?) -> Int? {
    if error == .rateLimited { return 100 }
    guard error == nil, let snapshot else { return nil }
    return snapshot.weeklyPercent
}
