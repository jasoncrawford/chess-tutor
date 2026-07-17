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

        if let gameID = CloudKitRemoteGameTransport.gameID(fromStatusSubscriptionID: subscriptionID) {
            bufferForReplayIfNeeded(.remoteGameStatus(gameID), application: application)
            Task {
                await DiagnosticsLog.shared.append(
                    category: "push",
                    "remoteGameStatus",
                    fields: ["gameID": gameID.rawValue, "subscriptionID": subscriptionID]
                )
            }
            NotificationCenter.default.post(
                name: .remoteGameStatusMayHaveChanged,
                object: nil,
                userInfo: [RemoteGameStatusPushUserInfoKey.gameID: gameID.rawValue]
            )
            completionHandler(.newData)
            return
        }

        if let gameID = CloudKitRemoteGameTransport.gameID(fromMoveSubscriptionID: subscriptionID) {
            bufferForReplayIfNeeded(.remoteGameMove(gameID), application: application)
            Task {
                await DiagnosticsLog.shared.append(
                    category: "push",
                    "remoteGameMove",
                    fields: ["gameID": gameID.rawValue, "subscriptionID": subscriptionID]
                )
            }
            NotificationCenter.default.post(
                name: .remoteGameMovesMayHaveChanged,
                object: nil,
                userInfo: [RemoteGameMovePushUserInfoKey.gameID: gameID.rawValue]
            )
            completionHandler(.newData)
            return
        }

        if let inviteID = CloudKitRemoteInviteTransport.inviteID(fromAcceptanceSubscriptionID: subscriptionID) {
            bufferForReplayIfNeeded(.remoteInviteAcceptance(inviteID), application: application)
            Task {
                await DiagnosticsLog.shared.append(
                    category: "push",
                    "remoteInviteAcceptance",
                    fields: ["inviteID": inviteID.rawValue, "subscriptionID": subscriptionID]
                )
            }
            NotificationCenter.default.post(
                name: .remoteInviteAcceptanceMayHaveChanged,
                object: nil,
                userInfo: [RemoteInviteAcceptancePushUserInfoKey.inviteID: inviteID.rawValue]
            )
            completionHandler(.newData)
            return
        }

        if let inviteID = CloudKitRemoteInviteTransport.inviteID(fromStatusSubscriptionID: subscriptionID) {
            bufferForReplayIfNeeded(.remoteInviteAcceptance(inviteID), application: application)
            Task {
                await DiagnosticsLog.shared.append(
                    category: "push",
                    "remoteInviteStatus",
                    fields: ["inviteID": inviteID.rawValue, "subscriptionID": subscriptionID]
                )
            }
            NotificationCenter.default.post(
                name: .remoteInviteAcceptanceMayHaveChanged,
                object: nil,
                userInfo: [RemoteInviteAcceptancePushUserInfoKey.inviteID: inviteID.rawValue]
            )
            completionHandler(.newData)
            return
        }

        if let playerID = CloudKitRemoteInviteTransport.playerID(fromIncomingInviteSubscriptionID: subscriptionID) {
            bufferForReplayIfNeeded(.remotePendingInvite(playerID), application: application)
            Task {
                await DiagnosticsLog.shared.append(
                    category: "push",
                    "remotePendingInvite",
                    fields: ["playerID": playerID.rawValue, "subscriptionID": subscriptionID]
                )
            }
            NotificationCenter.default.post(
                name: .remotePendingInvitesMayHaveChanged,
                object: nil,
                userInfo: [RemotePendingInvitePushUserInfoKey.playerID: playerID.rawValue]
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

    private func bufferForReplayIfNeeded(_ event: RemotePushNotificationEvent, application: UIApplication) {
        guard application.applicationState != .active else {
            return
        }
        RemotePushNotificationInbox.shared.record(event)
    }
}
