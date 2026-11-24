import AppKit
import BudgetGuardCore

/// Polls the usage source every `interval` seconds and on wake. Keeps the last good snapshot so a failure
/// is reported as (lastSnapshot, error) and the menu can grey the value instead of blanking it.
@MainActor
final class RefreshLoop {
    var onUpdate: ((UsageSnapshot?, UsageFetchError?) -> Void)?

    private let sourceProvider: () -> UsageSource
    private let interval: TimeInterval
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var inFlight = false
    private var rerun = false
    private var lastSnapshot: UsageSnapshot?

    init(sourceProvider: @escaping () -> UsageSource, interval: TimeInterval = 120) {
        self.sourceProvider = sourceProvider
        self.interval = interval
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The network is often not back right at wake: give it a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                MainActor.assumeIsolated { self?.refreshNow() }
            }
        }
        refreshNow()
    }

    /// Forget the last value (the source changed, the old number no longer applies).
    func resetSnapshot() { lastSnapshot = nil }

    func refreshNow() {
        guard !inFlight else { rerun = true; return }
        inFlight = true
        let source = sourceProvider()
        Task { @MainActor [weak self] in
            var fresh: UsageSnapshot?
            var failure: UsageFetchError?
            do {
                fresh = try await source.fetchSnapshot()
            } catch let e as UsageFetchError {
                failure = e
            } catch {
                failure = .network
            }
            guard let self else { return }
            self.inFlight = false
            if let fresh { self.lastSnapshot = fresh }
            self.onUpdate?(fresh ?? self.lastSnapshot, failure)
            if self.rerun { self.rerun = false; self.refreshNow() }
        }
    }
}
