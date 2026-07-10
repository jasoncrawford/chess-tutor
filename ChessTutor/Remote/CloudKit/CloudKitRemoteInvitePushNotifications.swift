import CloudKit
import Foundation
import UIKit

extension Notification.Name {
    static let remoteInviteAcceptanceMayHaveChanged = Notification.Name("RemoteInviteAcceptanceMayHaveChanged")
}

enum RemoteInviteAcceptancePushUserInfoKey {
    static let inviteID = "inviteID"
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
              let recordID = queryNotification.recordID else {
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
