import XCTest
@testable import ChessTutor

@MainActor
final class RemoteGameSessionControllerTests: XCTestCase {
    func testUploadedLocalMoveCanBeFetchedAndAppliedByRemotePlayerSession() async throws {
        let transport = InMemoryRemoteGameTransport()
        let whiteSession = GameSession()
        whiteSession.whitePlayer = .humanLocal
        whiteSession.blackPlayer = .remote(playerID: blackID.rawValue)
        let blackSession = GameSession()
        blackSession.whitePlayer = .remote(playerID: whiteID.rawValue)
        blackSession.blackPlayer = .humanLocal
        let whiteController = RemoteGameSessionController(
            descriptor: descriptor(localPlayerID: whiteID),
            transport: transport,
            initialState: .startingPosition()
        )
        let blackController = RemoteGameSessionController(
            descriptor: descriptor(localPlayerID: blackID),
            transport: transport,
            initialState: .startingPosition()
        )

        whiteSession.select(Square(file: .e, rank: 2))
        XCTAssertEqual(whiteSession.moveSelectedPiece(to: Square(file: .e, rank: 4)), .moved)
        let committedMove = try XCTUnwrap(whiteSession.finishTurn())
        try whiteController.recordCommittedLocalMove(committedMove, createdAt: Date(timeIntervalSince1970: 10))
        try await whiteController.uploadPendingMoves()

        let appliedMoves = try await blackController.fetchAndApplyRemoteMoves(to: blackSession)

        XCTAssertEqual(appliedMoves, [committedMove])
        XCTAssertEqual(blackSession.state.board[Square(file: .e, rank: 4)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(blackSession.state.board[Square(file: .e, rank: 2)])
        XCTAssertEqual(blackSession.state.sideToMove, .black)
        XCTAssertTrue(blackSession.localCanActForCurrentTurn)
        XCTAssertEqual(whiteController.syncStatus, .current)
        XCTAssertEqual(blackController.syncStatus, .current)
    }

    func testFailedUploadLeavesControllerInFailedSyncState() async throws {
        let transport = FailOnceRemoteGameTransport()
        let controller = RemoteGameSessionController(
            descriptor: descriptor(localPlayerID: whiteID),
            transport: transport,
            initialState: .startingPosition()
        )
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        try controller.recordCommittedLocalMove(move, createdAt: Date(timeIntervalSince1970: 10))

        do {
            try await controller.uploadPendingMoves()
            XCTFail("Expected upload to fail.")
        } catch {
            XCTAssertEqual(error as? RemoteGameCoordinator.Error, .transportFailed)
        }

        XCTAssertEqual(controller.syncStatus, .failed(.transportFailed))
    }

    private let gameID = RemoteGameID(rawValue: "game-1")
    private let whiteID = RemotePlayerID(rawValue: "white")
    private let blackID = RemotePlayerID(rawValue: "black")

    private func descriptor(localPlayerID: RemotePlayerID) -> RemoteGameDescriptor {
        RemoteGameDescriptor(
            id: gameID,
            protocolVersion: 1,
            status: .active,
            whitePlayer: RemotePlayerRef(id: whiteID, displayName: "Jason"),
            blackPlayer: RemotePlayerRef(id: blackID, displayName: "Maya"),
            localPlayerID: localPlayerID
        )
    }
}

private actor FailOnceRemoteGameTransport: RemoteGameTransport {
    private let backing = InMemoryRemoteGameTransport()
    private var shouldFailNextSend = true

    func sendMove(_ event: RemoteMoveEvent) async throws -> RemoteMoveAck {
        if shouldFailNextSend {
            shouldFailNextSend = false
            throw Error.intentionalFailure
        }
        return try await backing.sendMove(event)
    }

    func fetchMoves(gameID: RemoteGameID, after sequenceNumber: Int) async throws -> [RemoteMoveEvent] {
        try await backing.fetchMoves(gameID: gameID, after: sequenceNumber)
    }

    enum Error: Swift.Error {
        case intentionalFailure
    }
}
