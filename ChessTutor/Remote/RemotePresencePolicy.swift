import Foundation

enum RemotePresencePolicy {
    static let activeMovingExpiresAfter: TimeInterval = 5
    static let activeMovingResetDelay: TimeInterval = 3
    static let activeMovingRepublishInterval: TimeInterval = 2
    static let foregroundIdleExpiresAfter: TimeInterval = 10
    static let foregroundIdleHeartbeatInterval: TimeInterval = 5
    static let awayExpiresAfter: TimeInterval = 30

    static func shouldPublishActiveMoving(lastPublishedAt: Date?, now: Date) -> Bool {
        guard let lastPublishedAt else {
            return true
        }
        return now.timeIntervalSince(lastPublishedAt) >= activeMovingRepublishInterval
    }
}
