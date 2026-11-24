import AppKit
import BudgetGuardCore

/// Polls the usage source every `interval` seconds and on wake. Keeps the last good snapshot so a failure
/// is reported as (lastSnapshot, error) and the menu can grey the value instead of blanking it.
@MainActor
final class RefreshLoop {
    var onUpdate: ((UsageSnapshot?, UsageFetchError?) -> Void)?

    /// A suspended or dead web process must not freeze the percentage: give up and show it greyed.
    private static let fetchTimeout: Double = 45
    private let sourceProvider: () -> UsageSource
    private let interval: TimeInterval
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var gate = RefreshGate()
    private var lastSnapshot: UsageSnapshot?

    init(sourceProvider: @escaping () -> UsageSource, interval: TimeInterval = 120) {
        self.sourceProvider = sourceProvider
        self.interval = interval
    }

    func start() {
        timer?.invalidate()
        // .common so it keeps firing while the menu is open (event-tracking run loop mode).
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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

    /// Forget the last value (the source changed): any fetch still in flight is dropped when it completes.
    func resetSnapshot() {
        lastSnapshot = nil
        gate.reset()
    }

    func refreshNow() {
        guard let token = gate.request() else { return }
        let source = sourceProvider()
        Task { @MainActor [weak self] in
            var fresh: UsageSnapshot?
            var failure: UsageFetchError?
            do {
                fresh = try await withTimeout(seconds: Self.fetchTimeout) { try await source.fetchSnapshot() }
            } catch let e as UsageFetchError {
                failure = e
            } catch {
                failure = .network
            }
            guard let self else { return }
            let outcome = self.gate.complete(token)
            if outcome.accept {
                if let fresh { self.lastSnapshot = fresh }
                self.onUpdate?(fresh ?? self.lastSnapshot, failure)
            }
            if outcome.rerun { self.refreshNow() }
        }
    }
}
