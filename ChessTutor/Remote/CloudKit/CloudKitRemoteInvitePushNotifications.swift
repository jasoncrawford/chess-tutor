import CloudKit
import Foundation
import UIKit

extension Notification.Name {
    static let remoteInviteAcceptanceMayHaveChanged = Notification.Name("RemoteInviteAcceptanceMayHaveChanged")
    static let remoteGameMovesMayHaveChanged = Notification.Name("RemoteGameMovesMayHaveChanged")
    static let remoteGameStatusMayHaveChanged = Notification.Name("RemoteGameStatusMayHaveChanged")
}

enum RemoteInviteAcceptancePushUserInfoKey {
    static let inviteID = "inviteID"
}

enum RemoteGameMovePushUserInfoKey {
    static let gameID = "gameID"
}

enum RemoteGameStatusPushUserInfoKey {
    static let gameID = "gameID"
}

final class ChessTutorAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
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

        Task {
            await DiagnosticsLog.shared.append(
                category: "push",
                "ignored",
                fields: ["reason": "unknownSubscription", "subscriptionID": subscriptionID]
            )
        }
        completionHandler(.noData)
    }
}
