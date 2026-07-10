import CloudKit
import Foundation
import UIKit

extension Notification.Name {
    static let remoteInviteAcceptanceMayHaveChanged = Notification.Name("RemoteInviteAcceptanceMayHaveChanged")
    static let remoteGameMovesMayHaveChanged = Notification.Name("RemoteGameMovesMayHaveChanged")
}

enum RemoteInviteAcceptancePushUserInfoKey {
    static let inviteID = "inviteID"
}

enum RemoteGameMovePushUserInfoKey {
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
            completionHandler(.noData)
            return
        }

        if let gameID = CloudKitRemoteGameTransport.gameID(fromMoveSubscriptionID: subscriptionID) {
            NotificationCenter.default.post(
                name: .remoteGameMovesMayHaveChanged,
                object: nil,
                userInfo: [RemoteGameMovePushUserInfoKey.gameID: gameID.rawValue]
            )
            completionHandler(.newData)
            return
        }

        guard let recordID = queryNotification.recordID else {
            completionHandler(.noData)
            return
        }

        NotificationCenter.default.post(
            name: .remoteInviteAcceptanceMayHaveChanged,
            object: nil,
            userInfo: [RemoteInviteAcceptancePushUserInfoKey.inviteID: recordID.recordName]
        )
        completionHandler(.newData)
    }
}
