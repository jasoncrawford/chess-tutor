import XCTest
@testable import ChessTutor

final class RemoteIdentityStoreTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: storeURL.path) {
            try FileManager.default.removeItem(at: storeURL)
        }
        storeURL = nil
    }

    func testLoadsStableUnnamedLocalPlayerProfile() throws {
        let store = RemoteIdentityStore(fileURL: storeURL)

        let firstProfile = try store.loadLocalProfile()
        let secondProfile = try store.loadLocalProfile()

        XCTAssertEqual(firstProfile, secondProfile)
        XCTAssertFalse(firstProfile.id.rawValue.isEmpty)
        XCTAssertNil(firstProfile.displayName)
    }

    func testSavesTrimmedLocalDisplayName() throws {
        let store = RemoteIdentityStore(fileURL: storeURL)
        let unnamedProfile = try store.loadLocalProfile()

        let namedProfile = try store.saveLocalDisplayName("  Jason  ")

        XCTAssertEqual(namedProfile.id, unnamedProfile.id)
        XCTAssertEqual(namedProfile.displayName, "Jason")
        XCTAssertEqual(try RemoteIdentityStore(fileURL: storeURL).loadLocalProfile(), namedProfile)
    }

    func testMigratesPreviousMeDefaultToUnsetName() throws {
        let legacyState = """
        {
          "localProfile": {
            "id": {
              "rawValue": "legacy-local-player"
            },
            "displayName": "Me"
          },
          "knownPlayers": []
        }
        """
        try legacyState.write(to: storeURL, atomically: true, encoding: .utf8)

        XCTAssertNil(try RemoteIdentityStore(fileURL: storeURL).loadLocalProfile().displayName)
    }

    func testPreservesExplicitMeDisplayName() throws {
        let store = RemoteIdentityStore(fileURL: storeURL)

        _ = try store.saveLocalDisplayName("Me")

        XCTAssertEqual(try RemoteIdentityStore(fileURL: storeURL).loadLocalProfile().displayName, "Me")
    }

    func testRejectsEmptyLocalDisplayName() throws {
        let store = RemoteIdentityStore(fileURL: storeURL)

        XCTAssertThrowsError(try store.saveLocalDisplayName("   ")) { error in
            XCTAssertEqual(error as? RemoteIdentityStore.Error, .emptyDisplayName)
        }
    }

    func testPersistsKnownPlayersByID() throws {
        let store = RemoteIdentityStore(fileURL: storeURL)
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")

        try store.saveKnownPlayer(maya)
        try store.saveKnownPlayer(KnownRemotePlayer(id: maya.id, displayName: "Maya Crawford"))

        let reloadedStore = RemoteIdentityStore(fileURL: storeURL)
        XCTAssertEqual(
            try reloadedStore.loadKnownPlayers(),
            [KnownRemotePlayer(id: maya.id, displayName: "Maya Crawford")]
        )
    }
}
