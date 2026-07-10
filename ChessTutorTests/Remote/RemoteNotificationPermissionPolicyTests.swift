import UserNotifications
import XCTest
@testable import ChessTutor

final class RemoteNotificationPermissionPolicyTests: XCTestCase {
    func testRequestsOnlyWhenAuthorizationIsNotDetermined() {
        XCTAssertTrue(RemoteNotificationPermissionPolicy.shouldRequestAuthorization(for: .notDetermined))
        XCTAssertFalse(RemoteNotificationPermissionPolicy.shouldRequestAuthorization(for: .denied))
        XCTAssertFalse(RemoteNotificationPermissionPolicy.shouldRequestAuthorization(for: .authorized))
        XCTAssertFalse(RemoteNotificationPermissionPolicy.shouldRequestAuthorization(for: .provisional))
        XCTAssertFalse(RemoteNotificationPermissionPolicy.shouldRequestAuthorization(for: .ephemeral))
    }
}
