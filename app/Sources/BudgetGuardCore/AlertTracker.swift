import Foundation

public protocol AlertStateStore: AnyObject {
    func isNotified(_ threshold: Int) -> Bool
    func setNotified(_ threshold: Int, _ value: Bool)
}

public final class UserDefaultsAlertStateStore: AlertStateStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func key(_ threshold: Int) -> String { "alert.notified.\(threshold)" }

    public func isNotified(_ threshold: Int) -> Bool { defaults.bool(forKey: key(threshold)) }

    public func setNotified(_ threshold: Int, _ value: Bool) { defaults.set(value, forKey: key(threshold)) }
}

public struct AlertTracker {
    private let store: AlertStateStore
    private let thresholds: [Int]

    public init(store: AlertStateStore, thresholds: [Int] = [80, 95]) {
        self.store = store
        self.thresholds = thresholds.sorted()
    }

    /// Returns thresholds newly crossed (ascending). Sets the flag on cross, clears it when percent < threshold.
    public func thresholdsToAlert(for percent: Int) -> [Int] {
        var crossed: [Int] = []
        for threshold in thresholds {
            if percent >= threshold {
                if !store.isNotified(threshold) {
                    store.setNotified(threshold, true)
                    crossed.append(threshold)
                }
            } else if store.isNotified(threshold) {
                store.setNotified(threshold, false)
            }
        }
        return crossed
    }
}
