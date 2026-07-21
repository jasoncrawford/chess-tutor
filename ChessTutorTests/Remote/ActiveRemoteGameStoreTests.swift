import XCTest
@testable import ChessTutor

final class ActiveRemoteGameStoreTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActiveRemoteGameStoreTests-\(UUID().uuidString)")
            .appendingPathComponent("active-game.json")
    }

    override func tearDownWithError() throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
        storeURL = nil
    }

    func testSaveAndLoadActiveRemoteGameSnapshot() throws {
        let store = ActiveRemoteGameStore(fileURL: storeURL)
        let snapshot = makeSnapshot()

        try store.save(snapshot)

        let reloaded = try ActiveRemoteGameStore(fileURL: storeURL).load()
        XCTAssertEqual(reloaded, snapshot)
    }

    func testClearRemovesSavedSnapshot() throws {
        let store = ActiveRemoteGameStore(fileURL: storeURL)
        try store.save(makeSnapshot())

        try store.clear()

        XCTAssertNil(try ActiveRemoteGameStore(fileURL: storeURL).load())
    }

    private func makeSnapshot() -> ActiveRemoteGameSnapshot {
        ActiveRemoteGameSnapshot(
            descriptor: RemoteGameDescriptor(
                id: RemoteGameID(rawValue: "game-1"),
                protocolVersion: 1,
                status: .active,
                whitePlayer: RemotePlayerRef(id: RemotePlayerID(rawValue: "white"), displayName: "White"),
                blackPlayer: RemotePlayerRef(id: RemotePlayerID(rawValue: "black"), displayName: "Black"),
                localPlayerID: RemotePlayerID(rawValue: "white")
            ),
            acceptedEvents: [
                RemoteMoveEvent(
                    id: RemoteMoveEventID(rawValue: "event-1"),
                    gameID: RemoteGameID(rawValue: "game-1"),
                    sequenceNumber: 1,
                    actorPlayerID: RemotePlayerID(rawValue: "white"),
                    move: RemoteMoveCodec.encode(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))),
                    createdAt: Date(timeIntervalSince1970: 1),
                    protocolVersion: 1,
                    previousPositionFingerprint: PositionFingerprint(rawValue: "before"),
                    resultingPositionFingerprint: PositionFingerprint(rawValue: "after"),
                    notificationSummary: "White pawn to e4"
                )
            ],
            outbox: RemoteOutbox(),
            lastAppliedSequence: 1
        )
    }
}
