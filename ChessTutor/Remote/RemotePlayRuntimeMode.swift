import Foundation

enum RemotePlayRuntimeMode: Equatable, Sendable {
    case fakeLocal
    case cloudKit

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isRunningOnSimulator: Bool = Self.isRunningOnSimulator
    ) -> RemotePlayRuntimeMode {
        #if DEBUG
        if environment["CHESSTUTOR_REMOTE_INVITES"] == "cloudkit"
            || arguments.contains("-UseCloudKitRemoteInvites") {
            return .cloudKit
        }
        return isRunningOnSimulator ? .fakeLocal : .cloudKit
        #else
        return .cloudKit
        #endif
    }

    private static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
