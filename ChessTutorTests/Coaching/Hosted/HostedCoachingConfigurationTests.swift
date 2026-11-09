import Foundation
import XCTest
@testable import ChessTutor

final class HostedCoachingConfigurationTests: XCTestCase {
    func testAbsentBaseURLLeavesHostedModeDisabled() throws {
        let store = FakeHostedCredentialStore(token: "stored-token")

        XCTAssertNil(
            try HostedCoachingConfiguration.resolve(
                environment: [:],
                credentialStore: store,
                isDebugBuild: true
            )
        )
    }

    func testLaunchTokenBootstrapsCredentialStoreAndBuildsConfiguration() throws {
        let store = FakeHostedCredentialStore()

        let configuration = try XCTUnwrap(
            HostedCoachingConfiguration.resolve(
                environment: [
                    "CHESS_TUTOR_COACHING_BASE_URL": "http://127.0.0.1:8787",
                    "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "launch-token",
                ],
                credentialStore: store,
                isDebugBuild: true
            )
        )

        XCTAssertEqual(URL(string: "http://127.0.0.1:8787"), configuration.baseURL)
        XCTAssertEqual("launch-token", configuration.accessToken)
        XCTAssertEqual("launch-token", store.token)
        XCTAssertEqual(1, store.saveCount)
    }

    func testStoredTokenWorksWithoutLaunchSecret() throws {
        let store = FakeHostedCredentialStore(token: "stored-token")

        let configuration = try XCTUnwrap(
            HostedCoachingConfiguration.resolve(
                environment: ["CHESS_TUTOR_COACHING_BASE_URL": "https://coach.example"],
                credentialStore: store,
                isDebugBuild: false
            )
        )

        XCTAssertEqual("stored-token", configuration.accessToken)
        XCTAssertEqual(0, store.saveCount)
    }

    func testRejectsMissingTokenAndUnsafeURLs() {
        let missing = FakeHostedCredentialStore()
        XCTAssertThrowsError(
            try HostedCoachingConfiguration.resolve(
                environment: ["CHESS_TUTOR_COACHING_BASE_URL": "https://coach.example"],
                credentialStore: missing,
                isDebugBuild: false
            )
        )

        for value in [
            "http://coach.example",
            "https://user:password@coach.example",
            "https://coach.example/path",
            "https://coach.example?secret=value",
        ] {
            XCTAssertThrowsError(
                try HostedCoachingConfiguration.resolve(
                    environment: ["CHESS_TUTOR_COACHING_BASE_URL": value],
                    credentialStore: FakeHostedCredentialStore(token: "token"),
                    isDebugBuild: false
                ),
                value
            )
        }
    }
}

private final class FakeHostedCredentialStore: HostedCoachingCredentialStoring, @unchecked Sendable {
    var token: String?
    var saveCount = 0

    init(token: String? = nil) {
        self.token = token
    }

    func loadAccessToken() throws -> String? {
        token
    }

    func saveAccessToken(_ token: String) throws {
        self.token = token
        saveCount += 1
    }
}
