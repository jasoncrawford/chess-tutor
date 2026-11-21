import Foundation

enum HostedCoachingDiagnostics {
    /// Event time and sequence are captured by the session before asynchronous IO.
    static func record(_ event: DiagnosticsEvent) {
        Task {
            await DiagnosticsLog.shared.append(
                category: event.category, event.name,
                fields: event.fields, timestamp: event.timestamp
            )
        }
    }
}
