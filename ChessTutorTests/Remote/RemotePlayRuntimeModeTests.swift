import XCTest
@testable import ChessTutor

final class RemotePlayRuntimeModeTests: XCTestCase {
    func testDebugDefaultsToFakeLocalMode() {
        XCTAssertEqual(RemotePlayRuntimeMode.resolve(environment: [:], arguments: []), .fakeLocal)
    }

    func testDebugCanForceCloudKitModeWithEnvironmentVariable() {
        XCTAssertEqual(
            RemotePlayRuntimeMode.resolve(
                environment: ["CHESSTUTOR_REMOTE_INVITES": "cloudkit"],
                arguments: []
            ),
            .cloudKit
        )
    }

    func testDebugCanForceCloudKitModeWithLaunchArgument() {
        XCTAssertEqual(
            RemotePlayRuntimeMode.resolve(environment: [:], arguments: ["-UseCloudKitRemoteInvites"]),
            .cloudKit
        )
    }
}
