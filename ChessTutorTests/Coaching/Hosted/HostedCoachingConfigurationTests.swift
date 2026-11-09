import Foundation
import Security
import XCTest
@testable import ChessTutor

final class HostedCoachingConfigurationTests: XCTestCase {
    func testSetupSurvivesRelaunchWithoutEnvironment() throws {
        let store = FakeHostedCredentialStore()
        let initial = try HostedCoachingConfiguration.resolve(
            environment: ["CHESS_TUTOR_COACHING_BASE_URL": "https://coach.example", "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "family-token"],
            credentialStore: store, isDebugBuild: false
        )
        let relaunched = try HostedCoachingConfiguration.resolve(environment: [:], credentialStore: store, isDebugBuild: false)
        XCTAssertEqual(initial, relaunched)
        XCTAssertNotNil(HostedCoachingRuntime.resolveProvider(environment: [:], credentialStore: store))
    }

    func testDifferentServerCannotReuseTheSavedToken() throws {
        let store = FakeHostedCredentialStore()
        _ = try HostedCoachingConfiguration.resolve(
            environment: ["CHESS_TUTOR_COACHING_BASE_URL": "https://coach.example", "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "family-token"],
            credentialStore: store, isDebugBuild: false
        )
        XCTAssertThrowsError(try HostedCoachingConfiguration.resolve(
            environment: ["CHESS_TUTOR_COACHING_BASE_URL": "https://other.example"], credentialStore: store, isDebugBuild: false
        ))
    }

    func testAbsentBaseURLLeavesHostedModeDisabled() throws {
        let store = FakeHostedCredentialStore()

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
        XCTAssertEqual("launch-token", store.configuration?.accessToken)
        XCTAssertEqual(1, store.saveCount)
    }

    func testStoredTokenWorksWithoutLaunchSecret() throws {
        let store = FakeHostedCredentialStore(configuration: HostedCoachingConfiguration(baseURL: URL(string: "https://coach.example")!, accessToken: "stored-token"))

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
                    credentialStore: FakeHostedCredentialStore(),
                    isDebugBuild: false
                ),
                value
            )
        }
    }

    func testSameOriginNormalizationAndDifferentPortBoundary() throws {
        let store = FakeHostedCredentialStore(configuration: HostedCoachingConfiguration(baseURL: URL(string: "https://coach.example")!, accessToken: "token"))
        let same = try HostedCoachingConfiguration.resolve(environment: ["CHESS_TUTOR_COACHING_BASE_URL": "https://COACH.example:443/"], credentialStore: store, isDebugBuild: false)
        XCTAssertEqual("token", same?.accessToken)
        XCTAssertThrowsError(try HostedCoachingConfiguration.resolve(environment: ["CHESS_TUTOR_COACHING_BASE_URL": "https://coach.example:444"], credentialStore: store, isDebugBuild: false))
    }

    func testFailedReplacementPreservesOldPairAndFailsClosed() throws {
        let original = HostedCoachingConfiguration(baseURL: URL(string: "https://coach.example")!, accessToken: "old-token")
        let store = FakeHostedCredentialStore(configuration: original)
        store.failSave = true
        let environment = ["CHESS_TUTOR_COACHING_BASE_URL": "https://new.example", "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "new-token"]
        XCTAssertThrowsError(try HostedCoachingConfiguration.resolve(environment: environment, credentialStore: store, isDebugBuild: false))
        XCTAssertEqual(original, store.configuration)
        let provider = HostedCoachingRuntime.resolveProvider(environment: environment, credentialStore: store)
        XCTAssertNotNil(provider)
        XCTAssertFalse(provider is URLSessionHostedCoachingTransport)
    }

    func testSavedSettingsAreRevalidatedAndStoreErrorsDoNotEnableLocalFallback() throws {
        for configuration in [
            HostedCoachingConfiguration(baseURL: URL(string: "http://127.0.0.1:8787")!, accessToken: "token"),
            HostedCoachingConfiguration(baseURL: URL(string: "https://coach.example/path")!, accessToken: "token"),
            HostedCoachingConfiguration(baseURL: URL(string: "https://coach.example")!, accessToken: "token\r\nInjected: value"),
        ] {
            XCTAssertThrowsError(try HostedCoachingConfiguration.resolve(environment: [:], credentialStore: FakeHostedCredentialStore(configuration: configuration), isDebugBuild: false))
        }
        let store = FakeHostedCredentialStore()
        store.failLoad = true
        let provider = HostedCoachingRuntime.resolveProvider(environment: [:], credentialStore: store)
        XCTAssertNotNil(provider)
        XCTAssertFalse(provider is URLSessionHostedCoachingTransport)
    }

    func testRealKeychainPairRestoresInFreshStoreAndBuildsHostedTransport() throws {
        let service = "org.jasoncrawford.chesstutor.test.\(UUID().uuidString)"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "connection"]
        defer { SecItemDelete(query as CFDictionary) }
        let store = KeychainHostedCoachingCredentialStore(service: service)
        let initial = try HostedCoachingConfiguration.resolve(environment: ["CHESS_TUTOR_COACHING_BASE_URL": "https://coach.example", "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "first-token"], credentialStore: store, isDebugBuild: false)
        let fresh = KeychainHostedCoachingCredentialStore(service: service)
        XCTAssertEqual(initial, try HostedCoachingConfiguration.resolve(environment: [:], credentialStore: fresh, isDebugBuild: false))
        XCTAssertTrue(HostedCoachingRuntime.resolveProvider(environment: [:], credentialStore: fresh) is URLSessionHostedCoachingTransport)

        let updated = try HostedCoachingConfiguration.resolve(environment: ["CHESS_TUTOR_COACHING_BASE_URL": "https://new.example", "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "second-token"], credentialStore: store, isDebugBuild: false)
        XCTAssertEqual(updated, try fresh.loadConfiguration())
        XCTAssertEqual(errSecSuccess, SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data("malformed".utf8)] as CFDictionary))
        XCTAssertThrowsError(try fresh.loadConfiguration())
        XCTAssertNotNil(HostedCoachingRuntime.resolveProvider(environment: [:], credentialStore: fresh))
        XCTAssertFalse(HostedCoachingRuntime.resolveProvider(environment: [:], credentialStore: fresh) is URLSessionHostedCoachingTransport)
    }
}

private final class FakeHostedCredentialStore: HostedCoachingCredentialStoring, @unchecked Sendable {
    var configuration: HostedCoachingConfiguration?
    var saveCount = 0
    var failLoad = false
    var failSave = false

    init(configuration: HostedCoachingConfiguration? = nil) {
        self.configuration = configuration
    }

    func loadConfiguration() throws -> HostedCoachingConfiguration? {
        if failLoad { throw HostedCoachingConfigurationError.credentialStoreFailure }
        return configuration
    }

    func saveConfiguration(_ configuration: HostedCoachingConfiguration) throws {
        if failSave { throw HostedCoachingConfigurationError.credentialStoreFailure }
        self.configuration = configuration
        saveCount += 1
    }
}
