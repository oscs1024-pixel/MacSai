import Foundation

/// Thrown by ``withTimeout(_:_:)`` when the operation outlives its budget.
public struct TimeoutError: Error, Equatable {
    public init() {}
}

/// Run `operation`, returning its result, or throw ``TimeoutError`` if it does
/// not finish within `duration`.
///
/// IMPORTANT: Swift task cancellation is cooperative. If `operation` is blocked
/// inside a non-cancellable C/syscall (the exact failure this guards against in
/// the menu-bar stats loop), the underlying work keeps running on its executor
/// until it returns; this function only stops *waiting* on it. So this is a
/// safety net that keeps the UI responsive, not a way to kill a hung syscall.
/// Callers must still ensure the operation is fundamentally non-blocking (e.g.
/// use `statfs` rather than the purgeable-space disk key) so a wedged call can't
/// pile up behind a serial actor.
public func withTimeout<T: Sendable>(
    _ duration: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        // The first child to finish wins: the operation's value (or its own
        // thrown error) if it beats the clock, otherwise TimeoutError.
        return try await group.next()!
    }
}
