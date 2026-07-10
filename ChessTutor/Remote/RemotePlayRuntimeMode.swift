import Foundation

enum RemotePlayRuntimeMode: Equatable {
    case fakeLocal
    case cloudKit

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> RemotePlayRuntimeMode {
        #if DEBUG
        if environment["CHESSTUTOR_REMOTE_INVITES"] == "cloudkit"
            || arguments.contains("-UseCloudKitRemoteInvites") {
            return .cloudKit
        }
        return .fakeLocal
        #else
        return .cloudKit
        #endif
    }
}
