import Foundation

/// Coalescing + staleness rules for the refresh loop (pure state, no I/O).
/// At most one fetch in flight; requests made meanwhile collapse into one rerun;
/// `reset()` (source changed) makes the in-flight result stale so it is dropped.
public struct RefreshGate {
    private var generation = 0
    private var inFlight = false
    private var rerun = false

    public init() {}

    /// Returns a token when a fetch should start now; nil when one is in flight (a rerun is queued).
    public mutating func request() -> Int? {
        if inFlight { rerun = true; return nil }
        inFlight = true
        return generation
    }

    /// The source changed: results of fetches started before this call must be dropped.
    public mutating func reset() { generation += 1 }

    /// `accept`: the result belongs to the current generation. `rerun`: start another fetch now.
    public mutating func complete(_ token: Int) -> (accept: Bool, rerun: Bool) {
        inFlight = false
        let r = rerun
        rerun = false
        return (token == generation, r)
    }
}
