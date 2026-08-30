import Foundation
import XCTest
@testable import ChessTutor

final class ModelCoachingNeutralRequestBuilderTests: XCTestCase {
    func testStartingPositionBuildsOnlyRuleDerivedNeutralEvidence() {
        let snapshot = ModelCoachingNeutralSnapshot(
            committedState: .startingPosition(),
            learner: .white,
            positionRevision: 0,
            selectedSquare: nil,
            tentativeMove: nil,
            latestEvent: event(1, .helpOpened),
            episodeEvents: [event(1, .helpOpened)]
        )

        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: snapshot,
            requestID: "neutral-start"
        )

        XCTAssertEqual(request.schemaVersion, "model-coaching-neutral-request.v1")
        XCTAssertEqual(request.requestID, "neutral-start")
        XCTAssertEqual(request.positionRevision, 0)
        XCTAssertEqual(
            request.position.fen,
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        )
        XCTAssertEqual(request.position.sideToMove, "white")
        XCTAssertEqual(request.position.status, "ongoing")
        XCTAssertEqual(request.gameHistory, [])
        XCTAssertEqual(request.interaction.selectedSquare, nil)
        XCTAssertEqual(request.interaction.selectedPieceReference, nil)
        XCTAssertNil(request.interaction.tentativeMove)
        XCTAssertEqual(request.interaction.latestEvent, event(1, .helpOpened))
        XCTAssertEqual(request.interaction.episodeEvents, [event(1, .helpOpened)])
        XCTAssertEqual(request.pieces.map(\.id), request.pieces.map(\.id).sorted())
        XCTAssertEqual(request.legalMoves.map(\.id), request.legalMoves.map(\.id).sorted())
        XCTAssertEqual(
            request.occupiedSquareRelationships.map(\.id),
            request.occupiedSquareRelationships.map(\.id).sorted()
        )
        XCTAssertEqual(request.legalMoves.count, 20)
        XCTAssertTrue(request.legalMoves.allSatisfy { $0.capturePieceReference == nil })
        XCTAssertTrue(request.legalMoves.allSatisfy { !$0.givesCheck })
        XCTAssertTrue(request.legalMoves.allSatisfy { !$0.givesCheckmate })
        XCTAssertTrue(request.tentativeReplies.isEmpty)
        XCTAssertEqual(
            request.capabilities,
            ModelCoachingNeutralCapabilities(
                canSelectBoardPiece: true,
                canInspectSquare: true,
                canStageMove: false,
                canReplaceMove: false,
                canRemoveMove: false
            )
        )

        let json = encodedJSON(for: request)
        [
            "CoachingStage",
            "CoachingMoveOrigin",
            "MaterialTacticalEvaluator",
            "ModelCoachingSemanticOracle",
        ].forEach { forbidden in
            XCTAssertFalse(json.contains(forbidden), "unexpected policy value: \(forbidden)")
        }
    }

    func testSelectedKnightIncludesItsLegalMovesAndOccupiedRelationships() {
        let knight = square("f3")
        let knightID = "piece:white:knight:f3"
        let state = state(
            sideToMove: .white,
            pieces: [
                square("g1"): Piece(kind: .king, color: .white),
                knight: Piece(kind: .knight, color: .white),
                square("g2"): Piece(kind: .bishop, color: .white),
                square("g8"): Piece(kind: .king, color: .black),
                square("e4"): Piece(kind: .pawn, color: .black),
            ]
        )
        let snapshot = ModelCoachingNeutralSnapshot(
            committedState: state,
            learner: .white,
            positionRevision: 3,
            selectedSquare: knight,
            tentativeMove: nil,
            latestEvent: event(3, .pieceSelected, [knightID]),
            episodeEvents: [event(1, .helpOpened), event(3, .pieceSelected, [knightID])]
        )

        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: snapshot,
            requestID: "neutral-selected-knight"
        )

        XCTAssertEqual(request.interaction.selectedSquare, "f3")
        XCTAssertEqual(request.interaction.selectedPieceReference, knightID)
        XCTAssertEqual(
            request.legalMoves
                .filter { $0.sourcePieceReference == knightID }
                .map(\.id),
            LegalMoveGenerator.legalMoves(for: knight, by: .white, in: state)
                .map(ModelCoachingPositionEncoder.moveID)
                .sorted()
        )
        XCTAssertTrue(request.occupiedSquareRelationships.contains {
            $0.id == "relationship:attack:piece:black:pawn:e4->piece:white:knight:f3"
        })
        XCTAssertTrue(request.occupiedSquareRelationships.contains {
            $0.id == "relationship:defend:piece:white:bishop:g2->piece:white:knight:f3"
        })
        XCTAssertEqual(
            request.capabilities,
            ModelCoachingNeutralCapabilities(
                canSelectBoardPiece: true,
                canInspectSquare: true,
                canStageMove: true,
                canReplaceMove: false,
                canRemoveMove: false
            )
        )
    }

    func testTentativeBishopBlockIncludesLegalTentativeMoveAndAllCaptureOrCheckReplies() {
        let tentativeMove = Move(from: square("f1"), to: square("e2"))
        let state = state(
            sideToMove: .white,
            pieces: [
                square("e1"): Piece(kind: .king, color: .white),
                square("f1"): Piece(kind: .bishop, color: .white),
                square("h8"): Piece(kind: .king, color: .black),
                square("e8"): Piece(kind: .rook, color: .black),
            ]
        )
        let snapshot = ModelCoachingNeutralSnapshot(
            committedState: state,
            learner: .white,
            positionRevision: 4,
            selectedSquare: nil,
            tentativeMove: tentativeMove,
            latestEvent: event(4, .moveStaged, [ModelCoachingPositionEncoder.moveID(tentativeMove)]),
            episodeEvents: [
                event(1, .helpOpened),
                event(4, .moveStaged, [ModelCoachingPositionEncoder.moveID(tentativeMove)]),
            ]
        )

        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: snapshot,
            requestID: "neutral-tentative-bishop-block"
        )

        XCTAssertEqual(request.interaction.tentativeMove?.id, "move:f1-e2")
        XCTAssertEqual(request.interaction.tentativeMove?.san, "Be2")
        XCTAssertTrue(request.interaction.tentativeMove?.isLegal ?? false)
        XCTAssertFalse(request.interaction.tentativeMove?.givesCheck ?? true)
        XCTAssertFalse(request.interaction.tentativeMove?.givesCheckmate ?? true)

        let afterTentative = state.applyingUnchecked(tentativeMove)
        let expectedReplyIDs = LegalMoveGenerator.allLegalMoves(in: afterTentative)
            .filter { move in
                let outcome = afterTentative.applyingUnchecked(move)
                return LegalMoveGenerator.capture(for: move, in: afterTentative) != nil
                    || LegalMoveGenerator.isKingInCheck(outcome.sideToMove, in: outcome.board)
                    || {
                        if case .checkmate = outcome.result { return true }
                        return false
                    }()
            }
            .map(ModelCoachingPositionEncoder.moveID)
            .sorted()

        XCTAssertEqual(request.tentativeReplies.map(\.id), expectedReplyIDs)
        XCTAssertEqual(
            request.tentativeReplies.first?.capturePieceReference,
            "piece:white:bishop:e2"
        )
        XCTAssertEqual(
            request.capabilities,
            ModelCoachingNeutralCapabilities(
                canSelectBoardPiece: true,
                canInspectSquare: true,
                canStageMove: false,
                canReplaceMove: true,
                canRemoveMove: true
            )
        )
    }

    func testTentativeMoveNormalizesSelectedPieceReferenceBackToCommittedSourceSquare() {
        let tentativeMove = Move(from: square("a1"), to: square("a4"))
        let state = state(
            sideToMove: .white,
            pieces: [
                square("e1"): Piece(kind: .king, color: .white),
                square("a1"): Piece(kind: .rook, color: .white),
                square("h8"): Piece(kind: .king, color: .black),
                square("a4"): Piece(kind: .pawn, color: .black),
            ]
        )
        let snapshot = ModelCoachingNeutralSnapshot(
            committedState: state,
            learner: .white,
            positionRevision: 5,
            selectedSquare: square("a4"),
            tentativeMove: tentativeMove,
            latestEvent: event(5, .moveStaged, [ModelCoachingPositionEncoder.moveID(tentativeMove)]),
            episodeEvents: [
                event(1, .helpOpened),
                event(5, .moveStaged, [ModelCoachingPositionEncoder.moveID(tentativeMove)]),
            ]
        )

        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: snapshot,
            requestID: "neutral-staged-capture-selection"
        )

        XCTAssertEqual(request.interaction.selectedSquare, "a4")
        XCTAssertEqual(request.interaction.selectedPieceReference, "piece:white:rook:a1")
        XCTAssertEqual(request.interaction.tentativeMove?.capturePieceReference, "piece:black:pawn:a4")
    }

    func testOpponentPieceSelectionDoesNotAdvertiseLearnerStagingCapability() {
        let state = state(
            sideToMove: .white,
            pieces: [
                square("e1"): Piece(kind: .king, color: .white),
                square("h8"): Piece(kind: .king, color: .black),
                square("e5"): Piece(kind: .pawn, color: .black),
            ]
        )
        let snapshot = ModelCoachingNeutralSnapshot(
            committedState: state,
            learner: .white,
            positionRevision: 2,
            selectedSquare: square("e5"),
            tentativeMove: nil,
            latestEvent: event(2, .squareInspected, ["piece:black:pawn:e5"]),
            episodeEvents: [event(1, .helpOpened), event(2, .squareInspected, ["piece:black:pawn:e5"])]
        )

        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: snapshot,
            requestID: "neutral-opponent-selection"
        )

        XCTAssertEqual(request.interaction.selectedPieceReference, "piece:black:pawn:e5")
        XCTAssertFalse(request.capabilities.canStageMove)
        XCTAssertFalse(request.capabilities.canReplaceMove)
        XCTAssertFalse(request.capabilities.canRemoveMove)
    }

    func testLegalCaptureCarriesExactCapturedPieceReference() throws {
        let moves = [
            Move(from: square("e2"), to: square("e4")),
            Move(from: square("e7"), to: square("e5")),
            Move(from: square("g1"), to: square("f3")),
            Move(from: square("b8"), to: square("c6")),
        ]
        let state = replaying(moves)

        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: snapshot(for: state, positionRevision: moves.count),
            requestID: "neutral-capture"
        )

        let capture = try XCTUnwrap(request.legalMoves.first { $0.id == "move:f3-e5" })
        XCTAssertEqual(capture.capturePieceReference, "piece:black:pawn:e5")
        XCTAssertEqual(capture.san, "Nxe5")
    }

    func testCheckingAndMatingMovesUseAppliedRuleOutcomes() throws {
        let checkState = state(
            sideToMove: .white,
            pieces: [
                square("a1"): Piece(kind: .king, color: .white),
                square("d1"): Piece(kind: .queen, color: .white),
                square("h8"): Piece(kind: .king, color: .black),
            ]
        )
        let checkRequest = ModelCoachingNeutralRequestBuilder.build(
            snapshot: snapshot(for: checkState),
            requestID: "neutral-check"
        )
        let checkingMove = try XCTUnwrap(checkRequest.legalMoves.first { $0.id == "move:d1-h5" })
        XCTAssertTrue(checkingMove.givesCheck)
        XCTAssertFalse(checkingMove.givesCheckmate)

        let mateState = state(
            sideToMove: .white,
            pieces: [
                square("f6"): Piece(kind: .king, color: .white),
                square("g6"): Piece(kind: .queen, color: .white),
                square("h8"): Piece(kind: .king, color: .black),
            ]
        )
        let mateRequest = ModelCoachingNeutralRequestBuilder.build(
            snapshot: snapshot(for: mateState),
            requestID: "neutral-mate"
        )
        let matingMove = try XCTUnwrap(mateRequest.legalMoves.first { $0.id == "move:g6-g7" })
        XCTAssertTrue(matingMove.givesCheck)
        XCTAssertTrue(matingMove.givesCheckmate)
    }

    func testEightCommittedPliesKeepOrderedSanHistoryAndReplayToEncodedFen() {
        let moves = [
            Move(from: square("e2"), to: square("e4")),
            Move(from: square("e7"), to: square("e5")),
            Move(from: square("g1"), to: square("f3")),
            Move(from: square("b8"), to: square("c6")),
            Move(from: square("f1"), to: square("b5")),
            Move(from: square("a7"), to: square("a6")),
            Move(from: square("b5"), to: square("a4")),
            Move(from: square("g8"), to: square("f6")),
        ]
        var state = GameState.startingPosition()
        moves.forEach { state.apply($0) }

        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: snapshot(for: state, positionRevision: moves.count),
            requestID: "neutral-history"
        )

        XCTAssertEqual(request.gameHistory.map(\.canonicalMove), moves.map(ModelCoachingPositionEncoder.canonicalMove))
        XCTAssertEqual(request.gameHistory.map(\.displayNotation), MoveHistoryFormatter.notation(for: moves))
        XCTAssertEqual(request.position.fen, ModelCoachingPositionEncoder.fen(for: state))
        XCTAssertEqual(
            ModelCoachingPositionEncoder.fen(for: replaying(request.gameHistory.map(\.canonicalMove))),
            request.position.fen
        )
    }

    func testNeutralContractsAndBuilderStayOutsideLegacyPolicyDependencies() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contracts = try String(
            contentsOf: root.appendingPathComponent(
                "ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralContracts.swift"
            ),
            encoding: .utf8
        )
        let builder = try String(
            contentsOf: root.appendingPathComponent(
                "ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralRequestBuilder.swift"
            ),
            encoding: .utf8
        )

        [
            "CoachingMoveOrigin",
            "CoachingStage",
            "MaterialTacticalEvaluator",
            "CoachingAdvice",
            "ModelCoachingSemanticOracle",
            "private static func san(",
            "private static func checkSuffix(",
            "private static func disambiguation(",
        ].forEach { forbidden in
            XCTAssertFalse(contracts.contains(forbidden), "unexpected dependency in contracts: \(forbidden)")
            XCTAssertFalse(builder.contains(forbidden), "unexpected dependency in builder: \(forbidden)")
        }
        XCTAssertTrue(builder.contains("MoveHistoryFormatter.notation(for:"))
    }

    private func snapshot(
        for state: GameState,
        positionRevision: Int = 1
    ) -> ModelCoachingNeutralSnapshot {
        ModelCoachingNeutralSnapshot(
            committedState: state,
            learner: state.sideToMove,
            positionRevision: positionRevision,
            selectedSquare: nil,
            tentativeMove: nil,
            latestEvent: event(1, .helpOpened),
            episodeEvents: [event(1, .helpOpened)]
        )
    }

    private func replaying(_ canonicalMoves: [String]) -> GameState {
        canonicalMoves.reduce(into: GameState.startingPosition()) { state, canonicalMove in
            let move = LegalMoveGenerator
                .allLegalMoves(in: state)
                .first { ModelCoachingPositionEncoder.canonicalMove($0) == canonicalMove }!
            state.apply(move)
        }
    }

    private func replaying(_ moves: [Move]) -> GameState {
        moves.reduce(into: GameState.startingPosition()) { state, move in
            state.apply(move)
        }
    }

    private func event(
        _ sequence: Int,
        _ kind: ModelCoachingLearnerEventKind,
        _ referencedIDs: [String] = []
    ) -> ModelCoachingNeutralEpisodeEvent {
        ModelCoachingNeutralEpisodeEvent(
            sequence: sequence,
            kind: kind,
            referencedIDs: referencedIDs
        )
    }

    private func state(
        sideToMove: PieceColor,
        pieces: [Square: Piece]
    ) -> GameState {
        GameState(board: Board(pieces: pieces), sideToMove: sideToMove)
    }

    private func encodedJSON(for request: ModelCoachingNeutralRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try! encoder.encode(request), encoding: .utf8)!
    }

    private func square(_ algebraic: String) -> Square {
        let characters = Array(algebraic.utf8)
        return Square(
            file: Square.File(rawValue: Int(characters[0]) - 96)!,
            rank: Int(String(UnicodeScalar(characters[1])))!
        )
    }
}
