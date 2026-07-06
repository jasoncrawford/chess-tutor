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

    func testLoadsStableLocalPlayerProfile() throws {
        let store = RemoteIdentityStore(fileURL: storeURL)

        let firstProfile = try store.loadLocalProfile()
        let secondProfile = try store.loadLocalProfile()

        XCTAssertEqual(firstProfile, secondProfile)
        XCTAssertFalse(firstProfile.id.rawValue.isEmpty)
        XCTAssertEqual(firstProfile.displayName, "Me")
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
