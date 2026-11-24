import Foundation
import BudgetGuardCore

protocol UsageSource: AnyObject {
    /// Throws `UsageFetchError`.
    @MainActor func fetchSnapshot() async throws -> UsageSnapshot
}

enum SourceKind: String {
    case web, claudeCode

    static let defaultsKey = "usage.source"

    static var current: SourceKind {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(SourceKind.init(rawValue:)) ?? .web }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
