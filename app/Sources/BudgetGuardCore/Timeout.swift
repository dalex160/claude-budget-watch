import Foundation

/// Runs `operation` but gives up after `seconds` with `UsageFetchError.network`.
/// The caller is released at the deadline even if the operation never returns (a dead web process ignores cancellation).
public func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    let race = TimeoutRace<T>()
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
        race.install(cont)
        let work = Task {
            do { race.finish(.success(try await operation())) } catch { race.finish(.failure(error)) }
        }
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            race.finish(.failure(UsageFetchError.network))
        }
        race.attach(work, timer)
    }
}

private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Error>?
    private var done = false
    private var tasks: [Task<Void, Never>] = []

    func install(_ c: CheckedContinuation<T, Error>) { lock.lock(); cont = c; lock.unlock() }

    func attach(_ a: Task<Void, Never>, _ b: Task<Void, Never>) {
        lock.lock()
        let alreadyDone = done
        if !alreadyDone { tasks = [a, b] }
        lock.unlock()
        if alreadyDone { a.cancel(); b.cancel() }
    }

    /// First caller wins; later results are dropped.
    func finish(_ result: Result<T, Error>) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        let c = cont
        cont = nil
        let toCancel = tasks
        tasks = []
        lock.unlock()
        toCancel.forEach { $0.cancel() }
        c?.resume(with: result)
    }
}
