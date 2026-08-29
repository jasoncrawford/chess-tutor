import XCTest
import Observation
@testable import ChessTutor

final class GameSessionTests: XCTestCase {
    func testGameActivityDateFormatterUsesFriendlyRecentDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 12))!
        let time = now.formatted(date: .omitted, time: .shortened)

        XCTAssertEqual(GameActivityDateFormatter.string(from: now, now: now, calendar: calendar), "Today, \(time)")
        XCTAssertEqual(
            GameActivityDateFormatter.string(from: now.addingTimeInterval(-86_400), now: now, calendar: calendar),
            "Yesterday, \(time)"
        )
        XCTAssertEqual(
            GameActivityDateFormatter.string(from: now.addingTimeInterval(-2 * 86_400), now: now, calendar: calendar),
            "Wednesday, \(time)"
        )
    }

    @MainActor
    func testFinishedLocalGameCardShowsCheckmateInsteadOfAPlayerTurn() {
        let library = GameLibrary()
        let game = library.createLocalGame()
        let moves = [
            Move(from: Square(file: .f, rank: 2), to: Square(file: .f, rank: 3)),
            Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 5)),
            Move(from: Square(file: .g, rank: 2), to: Square(file: .g, rank: 4)),
            Move(from: Square(file: .d, rank: 8), to: Square(file: .h, rank: 4)),
        ]

        for move in moves {
            library.recordCommittedMove(move, in: game.id)
        }

        XCTAssertEqual(
            GameLibraryEntry.local(library.game(id: game.id)!).cardPresentation.status,
            "Checkmate. Black wins."
        )
        XCTAssertEqual(
            GameLibraryEntry.local(library.game(id: game.id)!).cardPresentation.statusIndicator,
            .finished
        )
        XCTAssertEqual(
            GameLibraryEntry.local(library.game(id: game.id)!).cardPresentation.compactDetail,
            "Checkmate. Black wins."
        )
    }

    func testPendingRemoteBoardKeepsItsJoinLinkAvailable() {
        let invite = RemotePendingInvite(
            id: RemoteInviteID(rawValue: "invite"),
            code: InviteCode(rawValue: "428193"),
            token: RemoteInviteToken(rawValue: "token-1"),
            inviter: RemotePlayerRef(id: RemotePlayerID(rawValue: "dad"), displayName: "Dad"),
            inviteeDisplayName: "Maya",
            whiteAssignment: .inviter,
            status: .pending,
            createdAt: .distantPast,
            expiresAt: .distantFuture,
            protocolVersion: 1
        )
        let board = ManagedPendingRemoteBoard(
            id: ManagedGameID(),
            invite: invite,
            role: .inviter,
            createdAt: .distantPast
        )

        XCTAssertEqual(board.inviteLink.absoluteString, "chesstutor://invite?code=428193&token=token-1")
        XCTAssertEqual(board.reopenedInvitationPresentation, .showInviteDetails)
    }

    @MainActor
    func testRemoteGameCardsDistinguishYourTurnFromWaiting() {
        let descriptor = RemoteGameDescriptor(
            id: RemoteGameID(rawValue: "game"),
            protocolVersion: 1,
            status: .active,
            whitePlayer: RemotePlayerRef(id: RemotePlayerID(rawValue: "me"), displayName: "Me"),
            blackPlayer: RemotePlayerRef(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya"),
            localPlayerID: RemotePlayerID(rawValue: "me")
        )
        let yourTurn = ManagedRemoteGame(
            id: ManagedGameID(),
            createdAt: .distantPast,
            snapshot: ActiveRemoteGameSnapshot(
                descriptor: descriptor,
                acceptedEvents: [],
                outbox: RemoteOutbox(),
                lastAppliedSequence: 0
            )
        )
        let waiting = ManagedRemoteGame(
            id: ManagedGameID(),
            createdAt: .distantPast,
            snapshot: ActiveRemoteGameSnapshot(
                descriptor: descriptor,
                acceptedEvents: [
                    RemoteMoveEvent(
                        id: RemoteMoveEventID(rawValue: "move"),
                        gameID: RemoteGameID(rawValue: "game"),
                        sequenceNumber: 1,
                        actorPlayerID: RemotePlayerID(rawValue: "me"),
                        move: RemoteMoveCodec.encode(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))),
                        createdAt: .distantPast,
                        protocolVersion: 1,
                        previousPositionFingerprint: PositionFingerprint(rawValue: "before"),
                        resultingPositionFingerprint: PositionFingerprint(rawValue: "after"),
                        notificationSummary: "White pawn to e4"
                    ),
                ],
                outbox: RemoteOutbox(),
                lastAppliedSequence: 1
            )
        )

        XCTAssertEqual(GameLibraryEntry.remote(yourTurn).cardPresentation.status, "Your turn")
        XCTAssertEqual(GameLibraryEntry.remote(yourTurn).cardPresentation.statusIndicator, .yourTurn)
        XCTAssertEqual(GameLibraryEntry.remote(waiting).cardPresentation.status, "Their turn")
        XCTAssertEqual(GameLibraryEntry.remote(waiting).cardPresentation.statusIndicator, .waiting)
    }

    @MainActor
    func testGameLibraryCreatesSeparateLocalGamesAndKeepsNewestFirst() {
        let start = Date(timeIntervalSince1970: 1_000)
        let library = GameLibrary(now: { start })

        let first = library.createLocalGame()
        library.recordCommittedMove(
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
            in: first.id,
            at: start.addingTimeInterval(10)
        )
        let second = library.createLocalGame(at: start.addingTimeInterval(20))

        XCTAssertEqual(library.games.map(\.id), [second.id, first.id])
        XCTAssertEqual(library.game(id: first.id)?.moves.count, 1)
        XCTAssertTrue(library.game(id: second.id)?.moves.isEmpty == true)
    }

    @MainActor
    func testGameCardUsesStartTimeForItsIdentityAndLastMoveForActivity() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let lastMovedAt = startedAt.addingTimeInterval(60)
        let library = GameLibrary(now: { startedAt })
        let game = library.createLocalGame()
        library.recordCommittedMove(
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
            in: game.id,
            at: lastMovedAt
        )

        let presentation = GameLibraryEntry.local(library.game(id: game.id)!).cardPresentation

        XCTAssertEqual(presentation.startedAt, startedAt)
        XCTAssertEqual(presentation.lastActivityAt, lastMovedAt)
        XCTAssertEqual(presentation.statusIndicator, .active)
    }

    @MainActor
    func testGameLibraryStoreRestoresGamesAndLastVisibleBoard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = GameLibraryStore(fileURL: directory.appendingPathComponent("games.json"))
        let library = GameLibrary(now: { Date(timeIntervalSince1970: 1_000) })
        let game = library.createLocalGame()
        library.recordCommittedMove(
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
            in: game.id
        )
        library.showBoard(game.id)

        try store.save(library.snapshot)
        let restored = try XCTUnwrap(try store.load())

        XCTAssertEqual(restored.games, library.snapshot.games)
        XCTAssertEqual(restored.route, .board(game.id))
    }

    @MainActor
    func testGameLibraryRouteChangesAreObservable() async {
        let library = GameLibrary()
        let game = library.createLocalGame()
        library.showBoard(game.id)
        let routeChanged = expectation(description: "route change is observed")

        withObservationTracking {
            _ = library.route
        } onChange: {
            routeChanged.fulfill()
        }

        library.showGames()

        await fulfillment(of: [routeChanged], timeout: 0.1)
    }

    @MainActor
    func testGameLibraryKeepsPendingRemoteBoardAlongsideLocalGames() {
        let library = GameLibrary()
        let local = library.createLocalGame()
        let invite = RemotePendingInvite(
            id: RemoteInviteID(rawValue: "invite"),
            code: InviteCode(rawValue: "123456"),
            token: RemoteInviteToken(rawValue: "token"),
            inviter: RemotePlayerRef(id: RemotePlayerID(rawValue: "dad"), displayName: "Dad"),
            inviteeDisplayName: "Maya",
            whiteAssignment: .inviter,
            status: .pending,
            createdAt: .distantPast,
            expiresAt: .distantFuture,
            protocolVersion: 1
        )

        let pending = library.createPendingRemoteBoard(invite)

        XCTAssertEqual(library.pendingRemoteBoards, [pending])
        XCTAssertEqual(library.games.map(\.id), [local.id])

        library.showBoard(pending.id)
        library.removePendingRemoteBoard(inviteID: invite.id)

        XCTAssertTrue(library.pendingRemoteBoards.isEmpty)
        XCTAssertEqual(library.route, .games)
    }

    @MainActor
    func testGameLibraryEntryProvidesBoardCardPresentation() {
        let library = GameLibrary()
        let local = library.createLocalGame()
        let invite = RemotePendingInvite(
            id: RemoteInviteID(rawValue: "invite"),
            code: InviteCode(rawValue: "123456"),
            token: RemoteInviteToken(rawValue: "token"),
            inviter: RemotePlayerRef(id: RemotePlayerID(rawValue: "dad"), displayName: "Dad"),
            inviteeDisplayName: "Maya",
            whiteAssignment: .inviter,
            status: .pending,
            createdAt: .distantPast,
            expiresAt: .distantFuture,
            protocolVersion: 1
        )
        let pending = library.createPendingRemoteBoard(invite, role: .inviter)

        XCTAssertEqual(GameLibraryEntry.local(local).cardPresentation.title, "Local game")
        XCTAssertEqual(GameLibraryEntry.local(local).cardPresentation.status, "White’s turn")
        XCTAssertEqual(GameLibraryEntry.pendingRemote(pending).cardPresentation.title, "Maya")
        XCTAssertEqual(GameLibraryEntry.pendingRemote(pending).cardPresentation.status, "Invitation sent")
    }

    @MainActor
    func testGameLibraryEntryCardPresentationReplaysBoardThumbnailState() {
        let library = GameLibrary()
        let local = library.createLocalGame()
        library.recordCommittedMove(
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
            in: local.id
        )

        let presentation = GameLibraryEntry.local(library.game(id: local.id)!).cardPresentation

        XCTAssertEqual(
            presentation.boardState.board[Square(file: .e, rank: 4)],
            Piece(kind: .pawn, color: .white)
        )
    }

    func testSelectingCurrentPlayersPieceExposesLegalDestinations() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))

        XCTAssertEqual(session.selectedSquare, Square(file: .e, rank: 2))
        XCTAssertTrue(session.legalDestinations.contains(Square(file: .e, rank: 3)))
        XCTAssertTrue(session.legalDestinations.contains(Square(file: .e, rank: 4)))
    }

    func testSelectedPieceInfoNamesSelectedPiece() {
        let session = GameSession()

        session.select(Square(file: .g, rank: 1))

        XCTAssertEqual(
            session.selectedPieceInfo,
            SelectedPieceInfo(
                piece: Piece(kind: .knight, color: .white),
                square: Square(file: .g, rank: 1),
                squareID: "g1",
                title: "White knight",
                movementSummary: "Moves in an L shape."
            )
        )
    }

    func testTappingEmptySquareAfterSelectionClearsQuietly() {
        let session = GameSession()

        session.select(Square(file: .g, rank: 1))
        session.select(Square(file: .a, rank: 6))

        XCTAssertNil(session.selectedPieceInfo)
        XCTAssertNil(session.selectedSquare)
        XCTAssertNil(session.message)
        XCTAssertTrue(session.legalDestinations.isEmpty)
    }

    func testTappingEmptySquareWithoutSelectionStaysQuiet() {
        let session = GameSession()

        session.select(Square(file: .a, rank: 6))

        XCTAssertNil(session.selectedSquare)
        XCTAssertNil(session.message)
    }

    func testSelectedPieceInfoIncludesSquareCoordinates() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))

        XCTAssertEqual(session.selectedPieceInfo?.squareID, "e2")
    }

    func testIllegalMoveReturnsFriendlyMessage() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 5))

        XCTAssertEqual(result, .illegal("That piece can't move there."))
        XCTAssertEqual(session.message, "That piece can't move there.")
        XCTAssertEqual(session.state.sideToMove, .white)
    }

    func testTappingInvalidEmptySquareClearsSelectionWithoutMoveMessage() {
        let origin = Square(file: .e, rank: 2)
        let emptySquare = Square(file: .a, rank: 3)
        let session = GameSession()
        session.select(origin)

        let result = session.tapEmptySquare(at: emptySquare)

        XCTAssertNil(result)
        XCTAssertEqual(session.state.board[origin], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.selectedSquare)
        XCTAssertNil(session.message)
    }

    func testTappingValidEmptySquareMovesWhenHintsAreHidden() {
        let origin = Square(file: .e, rank: 2)
        let destination = Square(file: .e, rank: 4)
        let session = GameSession()
        session.assistSettings.showLegalMovesOnSelection = false
        session.select(origin)

        let result = session.tapEmptySquare(at: destination)

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[destination], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[origin])
        XCTAssertEqual(session.selectedSquare, destination)
        XCTAssertTrue(session.canFinishTurn)
    }

    func testPromotionRequestClearsStaleIllegalMoveMessage() {
        let promotionFrom = Square(file: .e, rank: 7)
        let promotionTo = Square(file: .e, rank: 8)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        promotionFrom: Piece(kind: .pawn, color: .white),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(promotionFrom)
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 6))
        let result = session.moveSelectedPiece(to: promotionTo)

        XCTAssertEqual(result, .needsPromotion(from: promotionFrom, to: promotionTo))
        XCTAssertNil(session.message)
    }

    func testPromotionMoveRequestsPromotionChoice() {
        var board = Board()
        board[Square(file: .e, rank: 7)] = Piece(kind: .pawn, color: .white)
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        let session = GameSession(state: GameState(board: board, sideToMove: .white))

        session.select(Square(file: .e, rank: 7))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 8))

        XCTAssertEqual(result, .needsPromotion(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 8)))
    }

    func testPromoteStagesPromotionChoiceAndKeepsPromotedPieceSelected() {
        let promotionFrom = Square(file: .e, rank: 7)
        let promotionTo = Square(file: .e, rank: 8)
        var board = Board()
        board[promotionFrom] = Piece(kind: .pawn, color: .white)
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        let session = GameSession(state: GameState(board: board, sideToMove: .white))

        session.select(promotionFrom)
        session.message = "Choose a promotion piece."
        session.promote(from: promotionFrom, to: promotionTo, to: .knight)

        XCTAssertEqual(session.state.board[promotionTo], Piece(kind: .knight, color: .white))
        XCTAssertNil(session.state.board[promotionFrom])
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertTrue(session.canFinishTurn)
        XCTAssertEqual(session.selectedSquare, promotionTo)
        XCTAssertEqual(session.legalDestinations, [promotionFrom])
        XCTAssertNil(session.message)
    }

    func testLegalMoveWaitsForDoneBeforeAdvancingTurn() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 4)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 2)])
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertEqual(session.statusText, "White's turn")
        XCTAssertNil(session.guidanceText)
        XCTAssertTrue(session.canFinishTurn)

        session.finishTurn()

        XCTAssertEqual(session.state.sideToMove, .black)
        XCTAssertEqual(session.statusText, "Black's turn")
        XCTAssertFalse(session.canFinishTurn)
    }

    func testTentativeMoveCanBePutBackBeforeDone() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))
        session.select(Square(file: .e, rank: 4))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 2))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 2)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 4)])
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertNil(session.guidanceText)
    }

    func testGameInProgressReflectsTentativeAndCommittedMoves() {
        let session = GameSession()

        XCTAssertFalse(session.hasGameInProgress)

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertTrue(session.hasGameInProgress)

        session.finishTurn()

        XCTAssertTrue(session.hasGameInProgress)

        session.newGame()

        XCTAssertFalse(session.hasGameInProgress)
    }

    func testTentativeCaptureMovesCapturedPieceToTrayUntilPutBack() {
        let whitePawn = Square(file: .e, rank: 4)
        let blackPawn = Square(file: .d, rank: 5)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        XCTAssertTrue(session.capturedPieces.isEmpty)

        session.select(whitePawn)
        _ = session.moveSelectedPiece(to: blackPawn)

        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.tentative])

        session.select(blackPawn)
        _ = session.moveSelectedPiece(to: whitePawn)

        XCTAssertTrue(session.capturedPieces.isEmpty)
    }

    func testCaptureBecomesCommittedWhenTurnFinishesAndClearsOnNewGame() {
        let whitePawn = Square(file: .e, rank: 4)
        let blackPawn = Square(file: .d, rank: 5)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whitePawn)
        _ = session.moveSelectedPiece(to: blackPawn)
        session.finishTurn()

        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.committed])

        session.newGame()

        XCTAssertTrue(session.capturedPieces.isEmpty)
    }

    func testReplayingCommittedMovesRestoresCapturedPieces() {
        let session = GameSession(
            replayingCommittedMoves: [
                Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
                Move(from: Square(file: .d, rank: 7), to: Square(file: .d, rank: 5)),
                Move(from: Square(file: .e, rank: 4), to: Square(file: .d, rank: 5)),
            ]
        )

        XCTAssertEqual(session.state.board[Square(file: .d, rank: 5)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 4)])
        XCTAssertEqual(session.state.sideToMove, .black)
        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.capturedAt), [Square(file: .d, rank: 5)])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.committed])
    }

    #if DEBUG
    func testCaptureForTestingRemovesPieceFromBoardAndAddsCommittedCapture() {
        let session = GameSession()
        let square = Square(file: .a, rank: 7)

        session.captureForTesting(at: square)

        XCTAssertNil(session.state.board[square])
        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.capturedAt), [square])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.committed])
    }

    func testCaptureForTestingClearsTentativeMoveAndSelection() {
        let session = GameSession()
        let movedPawn = Square(file: .e, rank: 4)

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: movedPawn)
        session.select(movedPawn)

        session.captureForTesting(at: movedPawn)

        XCTAssertNil(session.state.board[movedPawn])
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertNil(session.selectedSquare)
        XCTAssertTrue(session.legalDestinations.isEmpty)
        XCTAssertNil(session.message)
    }

    func testPromoteForTestingReplacesPawnOnItsCurrentSquare() {
        let session = GameSession()
        let square = Square(file: .e, rank: 2)

        session.promoteForTesting(at: square, to: .queen)

        XCTAssertEqual(session.state.board[square], Piece(kind: .queen, color: .white))
    }

    func testPromoteForTestingIgnoresNonPawns() {
        let session = GameSession()
        let square = Square(file: .a, rank: 1)

        session.promoteForTesting(at: square, to: .queen)

        XCTAssertEqual(session.state.board[square], Piece(kind: .rook, color: .white))
    }
    #endif

    func testCapturedPieceAnimationIDDiffersFromCapturingPieceOnSameSquare() {
        let whitePawn = Square(file: .e, rank: 4)
        let blackPawn = Square(file: .d, rank: 5)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whitePawn)
        _ = session.moveSelectedPiece(to: blackPawn)

        guard let capturedPieceID = session.capturedPieces.first?.id else {
            XCTFail("Expected the captured pawn to appear in the captured-piece tray.")
            return
        }
        let capturingPieceID = session.pieceAnimationID(for: Piece(kind: .pawn, color: .white), at: blackPawn)

        XCTAssertNotEqual(capturedPieceID, capturingPieceID)
    }

    func testPawnCaptureThroughNormalOpeningKeepsCapturedPieceInTrayAfterDone() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))
        session.finishTurn()
        session.select(Square(file: .d, rank: 7))
        _ = session.moveSelectedPiece(to: Square(file: .d, rank: 5))
        session.finishTurn()

        session.select(Square(file: .e, rank: 4))
        _ = session.moveSelectedPiece(to: Square(file: .d, rank: 5))

        XCTAssertEqual(session.state.board[Square(file: .d, rank: 5)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 4)])
        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.tentative])

        session.finishTurn()

        XCTAssertEqual(session.state.board[Square(file: .d, rank: 5)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 4)])
        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.committed])
    }

    func testTentativeEnPassantMovesCapturedPawnToTrayUntilDone() {
        let whitePawn = Square(file: .e, rank: 5)
        let blackPawn = Square(file: .d, rank: 5)
        let enPassantDestination = Square(file: .d, rank: 6)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white,
                enPassantTarget: enPassantDestination
            )
        )

        session.select(whitePawn)
        let result = session.moveSelectedPiece(to: enPassantDestination)

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[enPassantDestination], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[whitePawn])
        XCTAssertNil(session.state.board[blackPawn])
        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.capturedAt), [blackPawn])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.tentative])

        session.finishTurn()

        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.capturedAt), [blackPawn])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.committed])
    }

    func testEnPassantSelectionMarksCapturedPawnSeparatelyFromDestination() {
        let whitePawn = Square(file: .e, rank: 5)
        let blackPawn = Square(file: .d, rank: 5)
        let enPassantDestination = Square(file: .d, rank: 6)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white,
                enPassantTarget: enPassantDestination
            )
        )

        session.select(whitePawn)

        XCTAssertTrue(session.legalDestinations.contains(enPassantDestination))
        XCTAssertFalse(session.captureIndicatorSquares.contains(enPassantDestination))
        XCTAssertEqual(session.captureIndicatorSquares, [blackPawn])
    }

    func testNormalCaptureSelectionMarksDestinationAsCapturedPiece() {
        let whitePawn = Square(file: .e, rank: 4)
        let blackPawn = Square(file: .d, rank: 5)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whitePawn)

        XCTAssertTrue(session.legalDestinations.contains(blackPawn))
        XCTAssertEqual(session.captureIndicatorSquares, [blackPawn])
    }

    func testTentativeEnPassantCanBePutBackBeforeDone() {
        let whitePawn = Square(file: .e, rank: 5)
        let blackPawn = Square(file: .d, rank: 5)
        let enPassantDestination = Square(file: .d, rank: 6)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white,
                enPassantTarget: enPassantDestination
            )
        )

        session.select(whitePawn)
        _ = session.moveSelectedPiece(to: enPassantDestination)
        session.select(enPassantDestination)
        let result = session.moveSelectedPiece(to: whitePawn)

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[whitePawn], Piece(kind: .pawn, color: .white))
        XCTAssertEqual(session.state.board[blackPawn], Piece(kind: .pawn, color: .black))
        XCTAssertNil(session.state.board[enPassantDestination])
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertTrue(session.capturedPieces.isEmpty)
    }

    func testCheckKeepsTurnStatusAndShowsGuidance() {
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        XCTAssertEqual(session.statusText, "White's turn")
        XCTAssertEqual(session.guidanceText, "Check! You must move to defend.")
    }

    func testSelectionGuidanceShowsAllowedMovesEvenWhenOnlySomeResolveCheck() {
        let whiteKing = Square(file: .e, rank: 1)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whiteKing: Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whiteKing)

        XCTAssertTrue(session.legalDestinations.contains(Square(file: .d, rank: 1)))
        XCTAssertTrue(session.legalDestinations.contains(Square(file: .e, rank: 2)))
    }

    func testCheckRuleViolationCanBeStagedButCannotFinishTurn() {
        let whiteKing = Square(file: .e, rank: 1)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whiteKing: Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whiteKing)
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 2))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 2)], Piece(kind: .king, color: .white))
        XCTAssertNil(session.state.board[whiteKing])
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertEqual(session.guidanceText, "Your king would still be in check. Move to defend your king.")

        session.finishTurn()

        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertEqual(session.guidanceText, "Your king would still be in check. Move to defend your king.")
    }

    func testMoveThatExposesKingCanBeStagedButCannotFinishTurn() {
        let whiteKing = Square(file: .e, rank: 1)
        let whiteRook = Square(file: .e, rank: 2)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whiteKing: Piece(kind: .king, color: .white),
                        whiteRook: Piece(kind: .rook, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whiteRook)
        let result = session.moveSelectedPiece(to: Square(file: .a, rank: 2))

        XCTAssertEqual(result, .moved)
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertEqual(session.guidanceText, "That move would put your king in check.")
    }

    func testHiddenLegalMoveHintsDoNotBlockLegalMoveExecution() {
        let session = GameSession()
        session.assistSettings.showLegalMovesOnSelection = false

        session.select(Square(file: .e, rank: 2))

        XCTAssertTrue(session.legalDestinations.isEmpty)

        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 4)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 2)])
    }

    func testRemotePlayerPieceCanBeInspectedWithoutMoveAffordances() {
        let session = GameSession()
        session.whitePlayer = .remote(playerID: "maya")

        session.select(Square(file: .e, rank: 2))

        XCTAssertEqual(session.selectedPieceInfo?.title, "White pawn")
        XCTAssertTrue(session.legalDestinations.isEmpty)
        XCTAssertNil(session.message)
    }

    func testLocalWaitingPlayerCanInspectOwnPieceDuringRemoteTurn() {
        let session = GameSession()
        session.whitePlayer = .remote(playerID: "maya")
        session.blackPlayer = .humanLocal

        session.select(Square(file: .e, rank: 7))

        XCTAssertEqual(session.selectedPieceInfo?.title, "Black pawn")
        XCTAssertTrue(session.legalDestinations.isEmpty)
        XCTAssertNil(session.message)
    }

    func testRemotePlayerCannotMovePieceOnTheirTurn() {
        let session = GameSession()
        session.whitePlayer = .remote(playerID: "maya")

        session.select(Square(file: .e, rank: 2))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertEqual(result, .illegal("It's not your turn."))
        XCTAssertEqual(session.message, "It's not your turn.")
    }

    func testEndedRemoteGameAllowsInspectionButPreventsMovement() {
        let session = GameSession()
        session.endRemoteGame(message: "Maya ended this game.")

        session.select(Square(file: .e, rank: 2))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertEqual(session.selectedPieceInfo?.title, "White pawn")
        XCTAssertTrue(session.legalDestinations.isEmpty)
        XCTAssertEqual(result, .illegal("Maya ended this game."))
        XCTAssertEqual(session.guidanceText, "Maya ended this game.")
    }

    func testNewGameClearsEndedRemoteGameLock() {
        let session = GameSession()
        session.endRemoteGame(message: "Maya ended this game.")

        session.newGame()

        XCTAssertTrue(session.localCanActForCurrentTurn)
        XCTAssertNil(session.guidanceText)
    }

    func testFinishTurnReturnsCommittedMove() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))
        let committedMove = session.finishTurn()

        XCTAssertEqual(committedMove, Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)))
    }

    func testCommitRemoteMoveAppliesMoveOnRemoteTurn() {
        let session = GameSession()
        session.blackPlayer = .remote(playerID: "maya")

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))
        session.finishTurn()

        let remoteMove = Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 5))
        let didCommit = session.commitRemoteMove(remoteMove)

        XCTAssertTrue(didCommit)
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 5)], Piece(kind: .pawn, color: .black))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 7)])
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertNil(session.message)
    }

    func testClearMessageMatchingClearsOnlyExpectedMessage() {
        let session = GameSession()
        session.message = "Could not sync remote move. Check your connection."

        session.clearMessage(matching: "Could not sync remote move. Check your connection.")

        XCTAssertNil(session.message)
    }

    func testClearMessageMatchingKeepsDifferentMessage() {
        let session = GameSession()
        session.message = "It's not your turn."

        session.clearMessage(matching: "Could not sync remote move. Check your connection.")

        XCTAssertEqual(session.message, "It's not your turn.")
    }

    func testCheckmateMoveShowsGameOverMessageAndAllowsIdentitySelection() {
        var board = Board()
        board[Square(file: .h, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .g, rank: 1)] = Piece(kind: .rook, color: .white)
        board[Square(file: .f, rank: 2)] = Piece(kind: .queen, color: .black)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        board[Square(file: .h, rank: 7)] = Piece(kind: .rook, color: .black)
        let session = GameSession(state: GameState(board: board, sideToMove: .black))

        session.select(Square(file: .h, rank: 7))
        let result = session.moveSelectedPiece(to: Square(file: .h, rank: 2))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.result, .ongoing)
        XCTAssertTrue(session.canFinishTurn)

        session.finishTurn()

        XCTAssertEqual(session.state.result, .checkmate(winner: .black))
        XCTAssertEqual(session.message, "Checkmate. Black wins.")

        session.select(Square(file: .g, rank: 1))

        XCTAssertEqual(session.selectedSquare, Square(file: .g, rank: 1))
        XCTAssertEqual(session.message, "Checkmate. Black wins.")
    }

    func testMoveAttemptAfterCheckmateKeepsGameOverMessage() {
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .g, rank: 1): Piece(kind: .rook, color: .white),
                        Square(file: .f, rank: 2): Piece(kind: .queen, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white,
                result: .checkmate(winner: .black)
            )
        )

        session.select(Square(file: .g, rank: 1))
        let result = session.moveSelectedPiece(to: Square(file: .g, rank: 2))

        XCTAssertEqual(result, .illegal("Checkmate. Black wins."))
        XCTAssertEqual(session.selectedSquare, Square(file: .g, rank: 1))
        XCTAssertTrue(session.legalDestinations.isEmpty)
        XCTAssertEqual(session.message, "Checkmate. Black wins.")
    }

    func testStalemateStatusAndSelectionAreTerminal() {
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                        Square(file: .g, rank: 6): Piece(kind: .king, color: .white),
                        Square(file: .f, rank: 7): Piece(kind: .queen, color: .white),
                    ]
                ),
                sideToMove: .black,
                result: .stalemate
            )
        )

        XCTAssertEqual(session.statusText, "Stalemate.")

        session.select(Square(file: .h, rank: 8))
        let result = session.moveSelectedPiece(to: Square(file: .g, rank: 8))

        XCTAssertEqual(result, .illegal("Stalemate."))
        XCTAssertEqual(session.selectedSquare, Square(file: .h, rank: 8))
        XCTAssertTrue(session.legalDestinations.isEmpty)
        XCTAssertEqual(session.message, "Stalemate.")
    }

    func testSelectingOpponentPieceInspectsItWithoutMakingItActionable() {
        let blackRook = Square(file: .d, rank: 6)
        let session = GameSession(state: inspectionPosition())

        session.select(blackRook)

        XCTAssertEqual(session.selectedSquare, blackRook)
        XCTAssertFalse(session.boardGuidance.selectedPaths.isEmpty)
        XCTAssertTrue(session.legalDestinations.isEmpty)
        XCTAssertEqual(
            session.moveSelectedPiece(to: Square(file: .d, rank: 5)),
            .illegal("Choose a white piece.")
        )
    }

    func testTentativeMoveStaysSelectedAndRefreshesItsDanger() {
        let pawn = Square(file: .e, rank: 2)
        let destination = Square(file: .e, rank: 4)
        let session = GameSession(state: tentativeDangerPosition())
        let initialRevision = session.analysisRevision

        session.select(pawn)
        session.toggleCoverage()

        XCTAssertEqual(session.analysisRevision, initialRevision)

        _ = session.moveSelectedPiece(to: destination)

        XCTAssertEqual(session.selectedSquare, destination)
        XCTAssertEqual(session.analysisRevision, initialRevision + 1)
        XCTAssertTrue(session.boardGuidance.threatenedSquares.contains(destination))
        XCTAssertTrue(session.boardGuidance.prominentThreatSquares.contains(destination))
        XCTAssertTrue(session.isCoverageVisible)
    }

    func testCoveragePersistsThroughTentativeMoveAndReversion() {
        let start = Square(file: .e, rank: 2)
        let destination = Square(file: .e, rank: 4)
        let session = GameSession()
        session.toggleCoverage()
        session.select(start)
        _ = session.moveSelectedPiece(to: destination)

        XCTAssertTrue(session.isCoverageVisible)
        XCTAssertEqual(session.selectedSquare, destination)

        _ = session.moveSelectedPiece(to: start)

        XCTAssertTrue(session.isCoverageVisible)
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertEqual(session.analysisRevision, 2)
    }

    func testFailedDoneKeepsCoverageVisible() {
        let pinnedRook = Square(file: .e, rank: 2)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        pinnedRook: Piece(kind: .rook, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )
        session.toggleCoverage()
        session.select(pinnedRook)
        _ = session.moveSelectedPiece(to: Square(file: .a, rank: 2))

        XCTAssertNil(session.finishTurn())
        XCTAssertTrue(session.isCoverageVisible)
    }

    func testSuccessfulLocalAndRemoteCommitsCloseCoverage() {
        let session = GameSession()
        session.blackPlayer = .remote(playerID: "maya")
        session.toggleCoverage()
        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertNotNil(session.finishTurn())
        XCTAssertFalse(session.isCoverageVisible)

        session.toggleCoverage()
        XCTAssertTrue(session.isCoverageVisible)

        XCTAssertTrue(
            session.commitRemoteMove(
                Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 5))
            )
        )
        XCTAssertFalse(session.isCoverageVisible)
    }

    func testNewGameAndRemoteGameEndCloseCoverage() {
        let session = GameSession()
        session.toggleCoverage()

        session.newGame()

        XCTAssertFalse(session.isCoverageVisible)

        session.toggleCoverage()
        session.endRemoteGame(message: "Maya ended this game.")

        XCTAssertFalse(session.isCoverageVisible)
        XCTAssertEqual(session.boardGuidance, .empty(sideToMove: .white))
    }

    func testPromotionKeepsPromotedPieceSelectedAndRefreshesAnalysis() {
        let source = Square(file: .e, rank: 7)
        let destination = Square(file: .e, rank: 8)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        source: Piece(kind: .pawn, color: .white),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.promote(from: source, to: destination, to: .knight)

        XCTAssertEqual(session.selectedSquare, destination)
        XCTAssertEqual(session.selectedPieceInfo?.piece, Piece(kind: .knight, color: .white))
        XCTAssertEqual(session.analysisRevision, 1)
    }

    func testTerminalSelectionKeepsIdentityButSuppressesMovementGuidance() {
        let losingKing = Square(file: .h, rank: 1)
        let whiteRook = Square(file: .g, rank: 1)
        let checkmateSession = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        losingKing: Piece(kind: .king, color: .white),
                        whiteRook: Piece(kind: .rook, color: .white),
                        Square(file: .f, rank: 2): Piece(kind: .queen, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white,
                result: .checkmate(winner: .black)
            )
        )

        checkmateSession.select(whiteRook)
        checkmateSession.toggleCoverage()

        XCTAssertEqual(checkmateSession.selectedSquare, whiteRook)
        XCTAssertEqual(checkmateSession.boardGuidance.threatenedSquares, [losingKing])
        XCTAssertTrue(checkmateSession.boardGuidance.selectedPaths.isEmpty)
        XCTAssertNil(checkmateSession.boardGuidance.coverage)
        XCTAssertFalse(checkmateSession.isCoverageVisible)

        let stalemateKing = Square(file: .h, rank: 8)
        let stalemateSession = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        stalemateKing: Piece(kind: .king, color: .black),
                        Square(file: .g, rank: 6): Piece(kind: .king, color: .white),
                        Square(file: .f, rank: 7): Piece(kind: .queen, color: .white),
                    ]
                ),
                sideToMove: .black,
                result: .stalemate
            )
        )

        stalemateSession.select(stalemateKing)

        XCTAssertEqual(stalemateSession.selectedSquare, stalemateKing)
        XCTAssertEqual(stalemateSession.boardGuidance, .empty(sideToMove: .black))
    }

    func testRemoteTurnStillAllowsReadOnlyInspectionAndCoverage() {
        let session = GameSession()
        session.whitePlayer = .remote(playerID: "maya")
        let blackPawn = Square(file: .e, rank: 7)

        session.select(blackPawn)
        session.toggleCoverage()

        XCTAssertEqual(session.selectedSquare, blackPawn)
        XCTAssertFalse(session.boardGuidance.selectedPaths.isEmpty)
        XCTAssertNotNil(session.boardGuidance.coverage)
        XCTAssertTrue(session.legalDestinations.isEmpty)
    }

    func testSelectionAndCoverageReuseAnalysisUntilPositionChanges() {
        let session = GameSession()
        let initialRevision = session.analysisRevision

        session.select(Square(file: .e, rank: 2))
        session.select(Square(file: .g, rank: 1))
        session.select(Square(file: .e, rank: 7))
        session.toggleCoverage()
        session.toggleCoverage()

        XCTAssertEqual(session.analysisRevision, initialRevision)

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertEqual(session.analysisRevision, initialRevision + 1)
    }

    func testEmptySquareAttemptAfterTentativeMoveRestoresCommittedBoard() {
        let origin = Square(file: .e, rank: 2)
        let stagedDestination = Square(file: .e, rank: 4)
        let emptySquare = Square(file: .a, rank: 3)
        let session = GameSession()
        session.toggleCoverage()
        session.select(origin)
        _ = session.moveSelectedPiece(to: stagedDestination)

        let result = session.tapEmptySquare(at: emptySquare)

        XCTAssertNil(result)
        XCTAssertEqual(session.state.board[origin], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[stagedDestination])
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertNil(session.selectedSquare)
        XCTAssertTrue(session.isCoverageVisible)
    }

    func testTappingAlternativeDestinationAtomicallyRedirectsTentativeMove() {
        let origin = Square(file: .d, rank: 1)
        let stagedDestination = Square(file: .d, rank: 3)
        let alternativeDestination = Square(file: .d, rank: 2)
        let queen = Piece(kind: .queen, color: .white)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        origin: queen,
                        Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )
        session.assistSettings.showLegalMovesOnSelection = false
        session.toggleCoverage()
        session.select(origin)
        _ = session.moveSelectedPiece(to: stagedDestination)
        let revisionAfterFirstMove = session.analysisRevision

        let result = session.tapEmptySquare(at: alternativeDestination)

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[alternativeDestination], queen)
        XCTAssertNil(session.state.board[origin])
        XCTAssertNil(session.state.board[stagedDestination])
        XCTAssertEqual(session.selectedSquare, alternativeDestination)
        XCTAssertTrue(session.canFinishTurn)
        XCTAssertTrue(session.isCoverageVisible)
        XCTAssertEqual(session.analysisRevision, revisionAfterFirstMove + 1)
    }

    func testPreparingSecondDragRestoresOriginAndAllowsAlternativeMove() {
        let origin = Square(file: .e, rank: 2)
        let stagedDestination = Square(file: .e, rank: 4)
        let alternativeDestination = Square(file: .e, rank: 3)
        let session = GameSession()
        session.toggleCoverage()
        session.select(origin)
        _ = session.moveSelectedPiece(to: stagedDestination)

        let preparedSource = session.prepareDrag(from: stagedDestination)

        XCTAssertEqual(preparedSource, origin)
        XCTAssertEqual(session.state.board[origin], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[stagedDestination])
        XCTAssertEqual(session.selectedSquare, origin)
        XCTAssertEqual(session.boardGuidance.selectedSquare, origin)
        XCTAssertTrue(session.legalDestinations.contains(alternativeDestination))
        XCTAssertTrue(session.isCoverageVisible)

        let result = session.moveSelectedPiece(to: alternativeDestination)

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(
            session.state.board[alternativeDestination],
            Piece(kind: .pawn, color: .white)
        )
        XCTAssertNil(session.state.board[origin])
        XCTAssertNil(session.state.board[stagedDestination])
        XCTAssertEqual(session.selectedSquare, alternativeDestination)
        XCTAssertTrue(session.canFinishTurn)
    }

    private func inspectionPosition() -> GameState {
        GameState(
            board: Board(
                pieces: [
                    Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                    Square(file: .b, rank: 4): Piece(kind: .bishop, color: .white),
                    Square(file: .d, rank: 1): Piece(kind: .rook, color: .white),
                    Square(file: .d, rank: 6): Piece(kind: .rook, color: .black),
                    Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )
    }

    private func tentativeDangerPosition() -> GameState {
        GameState(
            board: Board(
                pieces: [
                    Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                    Square(file: .e, rank: 2): Piece(kind: .pawn, color: .white),
                    Square(file: .b, rank: 7): Piece(kind: .bishop, color: .black),
                    Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )
    }
}
