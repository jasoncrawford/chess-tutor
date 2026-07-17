import CloudKit
import Foundation
import UIKit

extension Notification.Name {
    static let remoteInviteAcceptanceMayHaveChanged = Notification.Name("RemoteInviteAcceptanceMayHaveChanged")
    static let remotePendingInvitesMayHaveChanged = Notification.Name("RemotePendingInvitesMayHaveChanged")
    static let remoteGameMovesMayHaveChanged = Notification.Name("RemoteGameMovesMayHaveChanged")
    static let remoteGameStatusMayHaveChanged = Notification.Name("RemoteGameStatusMayHaveChanged")
}

enum RemoteInviteAcceptancePushUserInfoKey {
    static let inviteID = "inviteID"
}

enum RemotePendingInvitePushUserInfoKey {
    static let playerID = "playerID"
}

enum RemoteGameMovePushUserInfoKey {
    static let gameID = "gameID"
}

enum RemoteGameStatusPushUserInfoKey {
    static let gameID = "gameID"
}

enum RemotePushNotificationEvent: Equatable {
    case remoteInviteAcceptance(RemoteInviteID)
    case remotePendingInvite(RemotePlayerID)
    case remoteGameMove(RemoteGameID)
    case remoteGameStatus(RemoteGameID)
}

enum RemotePushNotificationRouting {
    struct RoutedNotification: Equatable {
        let event: RemotePushNotificationEvent
        let name: Notification.Name
        let userInfo: [String: String]
        let diagnosticsName: String
        let diagnosticsFields: [String: String]
    }

    static func route(subscriptionID: String) -> RoutedNotification? {
        if let gameID = CloudKitRemoteGameTransport.gameID(fromStatusSubscriptionID: subscriptionID) {
            return RoutedNotification(
                event: .remoteGameStatus(gameID),
                name: .remoteGameStatusMayHaveChanged,
                userInfo: [RemoteGameStatusPushUserInfoKey.gameID: gameID.rawValue],
                diagnosticsName: "remoteGameStatus",
                diagnosticsFields: ["gameID": gameID.rawValue, "subscriptionID": subscriptionID]
            )
        }

        if let gameID = CloudKitRemoteGameTransport.gameID(fromMoveSubscriptionID: subscriptionID) {
            return RoutedNotification(
                event: .remoteGameMove(gameID),
                name: .remoteGameMovesMayHaveChanged,
                userInfo: [RemoteGameMovePushUserInfoKey.gameID: gameID.rawValue],
                diagnosticsName: "remoteGameMove",
                diagnosticsFields: ["gameID": gameID.rawValue, "subscriptionID": subscriptionID]
            )
        }

        if let inviteID = CloudKitRemoteInviteTransport.inviteID(fromAcceptanceSubscriptionID: subscriptionID) {
            return RoutedNotification(
                event: .remoteInviteAcceptance(inviteID),
                name: .remoteInviteAcceptanceMayHaveChanged,
                userInfo: [RemoteInviteAcceptancePushUserInfoKey.inviteID: inviteID.rawValue],
                diagnosticsName: "remoteInviteAcceptance",
                diagnosticsFields: ["inviteID": inviteID.rawValue, "subscriptionID": subscriptionID]
            )
        }

        if let inviteID = CloudKitRemoteInviteTransport.inviteID(fromStatusSubscriptionID: subscriptionID) {
            return RoutedNotification(
                event: .remoteInviteAcceptance(inviteID),
                name: .remoteInviteAcceptanceMayHaveChanged,
                userInfo: [RemoteInviteAcceptancePushUserInfoKey.inviteID: inviteID.rawValue],
                diagnosticsName: "remoteInviteStatus",
                diagnosticsFields: ["inviteID": inviteID.rawValue, "subscriptionID": subscriptionID]
            )
        }

        if let playerID = CloudKitRemoteInviteTransport.playerID(fromIncomingInviteSubscriptionID: subscriptionID) {
            return RoutedNotification(
                event: .remotePendingInvite(playerID),
                name: .remotePendingInvitesMayHaveChanged,
                userInfo: [RemotePendingInvitePushUserInfoKey.playerID: playerID.rawValue],
                diagnosticsName: "remotePendingInvite",
                diagnosticsFields: ["playerID": playerID.rawValue, "subscriptionID": subscriptionID]
            )
        }

        return nil
    }

    @discardableResult
    static func recordLaunchNotification(
        subscriptionID: String,
        inbox: RemotePushNotificationInbox = .shared
    ) -> RoutedNotification? {
        guard let routedNotification = route(subscriptionID: subscriptionID) else {
            return nil
        }
        inbox.record(routedNotification.event)
        return routedNotification
    }
}

final class RemotePushNotificationInbox: @unchecked Sendable {
    static let shared = RemotePushNotificationInbox()

    private let lock = NSLock()
    private var events: [RemotePushNotificationEvent] = []

    private init() {}

    func record(_ event: RemotePushNotificationEvent) {
        lock.withLock {
            events.append(event)
        }
    }

    func drain() -> [RemotePushNotificationEvent] {
        lock.withLock {
            defer { events.removeAll() }
            return events
        }
    }
}

final class ChessTutorAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        Task {
            await DiagnosticsLog.shared.append(
                category: "push",
                "registrationRequested"
            )
        }
        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            handleLaunchRemoteNotification(userInfo)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            await DiagnosticsLog.shared.append(
                category: "push",
                "registrationSucceeded",
                fields: ["deviceTokenBytes": "\(deviceToken.count)"]
            )
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        Task {
            await DiagnosticsLog.shared.append(
                category: "push",
                "registrationFailed",
                fields: ["error": String(describing: error)]
            )
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let queryNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
              let subscriptionID = queryNotification.subscriptionID else {
            Task {
                await DiagnosticsLog.shared.append(
                    category: "push",
                    "ignored",
                    fields: ["reason": "notQueryNotification"]
                )
            }
            completionHandler(.noData)
            return
        }

        if let routedNotification = RemotePushNotificationRouting.route(subscriptionID: subscriptionID) {
            bufferForReplayIfNeeded(routedNotification.event, application: application)
            logRoutedNotification(routedNotification)
            NotificationCenter.default.post(
                name: routedNotification.name,
                object: nil,
                userInfo: routedNotification.userInfo
            )
            completionHandler(.newData)
            return
        }

        Task {
            await DiagnosticsLog.shared.append(
                category: "push",
                "ignored",
                fields: ["reason": "unknownSubscription", "subscriptionID": subscriptionID]
            )
        }
        completionHandler(.noData)
    }

    private func handleLaunchRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        guard let queryNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
              let subscriptionID = queryNotification.subscriptionID else {
            Task {
                await DiagnosticsLog.shared.append(
                    category: "push",
                    "launchIgnored",
                    fields: ["reason": "notQueryNotification"]
                )
            }
            return
        }

        guard let routedNotification = RemotePushNotificationRouting.recordLaunchNotification(
            subscriptionID: subscriptionID
        ) else {
            Task {
                await DiagnosticsLog.shared.append(
                    category: "push",
                    "launchIgnored",
                    fields: ["reason": "unknownSubscription", "subscriptionID": subscriptionID]
                )
            }
            return
        }

        logRoutedNotification(
            routedNotification,
            extraFields: ["source": "launchOptions"]
        )
    }

    private func bufferForReplayIfNeeded(_ event: RemotePushNotificationEvent, application: UIApplication) {
        guard application.applicationState != .active else {
            return
        }
        RemotePushNotificationInbox.shared.record(event)
    }

    private func logRoutedNotification(
        _ routedNotification: RemotePushNotificationRouting.RoutedNotification,
        extraFields: [String: String] = [:]
    ) {
        Task {
            await DiagnosticsLog.shared.append(
                category: "push",
                routedNotification.diagnosticsName,
                fields: routedNotification.diagnosticsFields
                    .merging(extraFields) { current, _ in current }
            )
        }
    }
}
