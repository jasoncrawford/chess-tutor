import XCTest
@testable import ChessTutor

final class RemotePlayRuntimeModeTests: XCTestCase {
    func testDebugDefaultsToFakeLocalModeOnSimulator() {
        XCTAssertEqual(
            RemotePlayRuntimeMode.resolve(environment: [:], arguments: [], isRunningOnSimulator: true),
            .fakeLocal
        )
    }

    func testDebugDefaultsToCloudKitModeOnPhysicalDevice() {
        XCTAssertEqual(
            RemotePlayRuntimeMode.resolve(environment: [:], arguments: [], isRunningOnSimulator: false),
            .cloudKit
        )
    }

    func testDebugCanForceCloudKitModeWithEnvironmentVariable() {
        XCTAssertEqual(
            RemotePlayRuntimeMode.resolve(
                environment: ["CHESSTUTOR_REMOTE_INVITES": "cloudkit"],
                arguments: [],
                isRunningOnSimulator: true
            ),
            .cloudKit
        )
    }

    func testDebugCanForceCloudKitModeWithLaunchArgument() {
        XCTAssertEqual(
            RemotePlayRuntimeMode.resolve(
                environment: [:],
                arguments: ["-UseCloudKitRemoteInvites"],
                isRunningOnSimulator: true
            ),
            .cloudKit
        )
    }
}
