import UserNotifications

enum RemoteNotificationPermissionPolicy {
    static func shouldRequestAuthorization(for status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined
    }
}
