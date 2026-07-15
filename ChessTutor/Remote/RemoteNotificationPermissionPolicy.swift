import UserNotifications

enum RemoteNotificationPermissionPolicy {
    static func shouldRequestAuthorization(for status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    static func diagnosticsName(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        @unknown default:
            return "unknown"
        }
    }
}
