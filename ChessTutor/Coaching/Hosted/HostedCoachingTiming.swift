import Foundation

/// Monotonic timing keeps debounce independent of wall-clock corrections.
struct HostedCoachingTiming: Sendable {
    let debounceSeconds: TimeInterval
    let now: @Sendable () -> TimeInterval
    let sleep: @Sendable (TimeInterval) async throws -> Void

    init(
        debounceSeconds: TimeInterval = 0.4,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        }
    ) {
        precondition(debounceSeconds.isFinite && debounceSeconds >= 0)
        self.debounceSeconds = debounceSeconds
        self.now = now
        self.sleep = sleep
    }
}
