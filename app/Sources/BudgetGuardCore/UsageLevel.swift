import Foundation

public enum UsageLevel: Equatable {
    case normal, warning, critical

    public init(percent: Int) {
        switch percent {
        case ..<70: self = .normal
        case 70..<90: self = .warning
        default: self = .critical
        }
    }
}

public enum UsageFetchError: Error, Equatable {
    case notLoggedIn, network, cloudflare, rateLimited, unsupportedPlan, malformed
}
