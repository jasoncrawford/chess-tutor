import XCTest
@testable import ChessTutor

final class ModelCoachingRequestBuilderTests: XCTestCase {
    func testCanonicalPositionAndReferenceEncodings() {
        XCTAssertEqual(
            ModelCoachingPositionEncoder.fen(for: .startingPosition()),
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        )
        XCTAssertEqual(
            ModelCoachingPositionEncoder.moveID(Move(from: square("g1"), to: square("f3"))),
            "move:g1-f3"
        )
        XCTAssertEqual(
            ModelCoachingPositionEncoder.moveID(
                Move(from: square("e1"), to: square("g1"), special: .castleKingside)
            ),
            "move:e1-g1:castle-kingside"
        )
        XCTAssertEqual(
            ModelCoachingPositionEncoder.moveID(
                Move(from: square("a7"), to: square("a8"), special: .promotion(.queen))
            ),
            "move:a7-a8:promote-queen"
        )
        XCTAssertEqual(
            ModelCoachingPositionEncoder.pieceID(
                Piece(kind: .queen, color: .white),
                at: square("f3")
            ),
            "piece:white:queen:f3"
        )
        XCTAssertEqual(
            ModelCoachingPositionEncoder.relationshipID(
                kind: .attacks,
                source: "piece:white:queen:f3",
                target: "piece:black:pawn:f7"
            ),
            "relationship:attack:piece:white:queen:f3->piece:black:pawn:f7"
        )
    }

    func testHistoryUsesCanonicalMoveIDsAndExistingDisplayNotation() {
        let moves = [
            Move(from: square("e2"), to: square("e4")),
            Move(from: square("e7"), to: square("e5")),
        ]

        XCTAssertEqual(
            moves.map(ModelCoachingPositionEncoder.moveID),
            ["move:e2-e4", "move:e7-e5"]
        )
        XCTAssertEqual(MoveHistoryFormatter.notation(for: moves), ["e4", "e5"])
    }

    func testControlledSquaresIncludeMechanicalPieceTargets() {
        let state = GameState(
            board: Board(pieces: [
                square("e1"): Piece(kind: .king, color: .white),
                square("e8"): Piece(kind: .king, color: .black),
                square("e4"): Piece(kind: .pawn, color: .white),
                square("c3"): Piece(kind: .knight, color: .white),
                square("a1"): Piece(kind: .rook, color: .white),
                square("a3"): Piece(kind: .pawn, color: .white),
            ]),
            sideToMove: .white
        )

        XCTAssertEqual(
            LegalMoveGenerator.controlledSquares(from: square("e4"), in: state),
            [square("d5"), square("f5")]
        )
        XCTAssertEqual(
            LegalMoveGenerator.controlledSquares(from: square("c3"), in: state),
            [square("a2"), square("a4"), square("b1"), square("b5"), square("d1"), square("d5"), square("e2"), square("e4")]
        )
        XCTAssertTrue(LegalMoveGenerator.controlledSquares(from: square("a1"), in: state).contains(square("a3")))
        XCTAssertFalse(LegalMoveGenerator.controlledSquares(from: square("a1"), in: state).contains(square("a4")))
        XCTAssertTrue(LegalMoveGenerator.controlledSquares(from: square("e1"), in: state).contains(square("d2")))
    }

    func testStartingPositionBuildsCompleteLegalMovesAndMechanicalRelationships() {
        let snapshot = makeSnapshot(state: .startingPosition())

        let request = ModelCoachingRequestBuilder.build(
            snapshot: snapshot,
            requestID: "request-start",
            promptVersion: "prompt.v1"
        )

        XCTAssertEqual(request.currentPosition.fen, ModelCoachingPositionEncoder.fen(for: .startingPosition()))
        XCTAssertEqual(
            request.chessEvidence.legalMoves.map(\.id),
            ModelCoachingPositionEncoder.orderedMoves(LegalMoveGenerator.allLegalMoves(in: .startingPosition()))
                .map(ModelCoachingPositionEncoder.moveID)
        )
        XCTAssertTrue(request.chessEvidence.legalMoves.allSatisfy(\.isLegal))
        XCTAssertEqual(request.chessEvidence.scope.legalMoves, .exhaustive)
        XCTAssertEqual(request.chessEvidence.scope.relationships, .exhaustive)
        XCTAssertEqual(request.chessEvidence.scope.immediateReplies, .bounded)
        XCTAssertTrue(request.chessEvidence.relationships.contains {
            $0.id == "relationship:defend:piece:white:king:e1->piece:white:pawn:d2"
        })
        XCTAssertFalse(encodedJSON(for: request).contains("noPieceNeedsHelp"))
    }

    func testQueenAttackAndKingDefenseAreMechanicalRelationshipsWithoutPolicy() {
        let state = state(
            sideToMove: .white,
            pieces: [
                square("e1"): Piece(kind: .king, color: .white),
                square("g8"): Piece(kind: .king, color: .black),
                square("f3"): Piece(kind: .queen, color: .white),
                square("f7"): Piece(kind: .pawn, color: .black),
            ]
        )

        let request = ModelCoachingRequestBuilder.build(
            snapshot: makeSnapshot(state: state),
            requestID: "request-queen",
            promptVersion: "prompt.v1"
        )
        let relationships = Set(request.chessEvidence.relationships.map(\.id))

        XCTAssertTrue(relationships.contains("relationship:attack:piece:white:queen:f3->piece:black:pawn:f7"))
        XCTAssertTrue(relationships.contains("relationship:defend:piece:black:king:g8->piece:black:pawn:f7"))
        XCTAssertFalse(encodedJSON(for: request).contains("CoachingStage"))
        XCTAssertFalse(encodedJSON(for: request).contains("preferred"))
    }

    func testEndangeredKnightCarriesEvaluatorDangerAndProfitableReplyFacts() {
        let knight = square("f3")
        let capture = Move(from: square("e4"), to: knight)
        let state = state(
            sideToMove: .white,
            pieces: [
                square("g1"): Piece(kind: .king, color: .white),
                square("g8"): Piece(kind: .king, color: .black),
                knight: Piece(kind: .knight, color: .white),
                square("e4"): Piece(kind: .pawn, color: .black),
            ]
        )

        let request = ModelCoachingRequestBuilder.build(
            snapshot: makeSnapshot(state: state),
            requestID: "request-danger",
            promptVersion: "prompt.v1"
        )

        XCTAssertTrue(request.chessEvidence.tacticalFacts.contains {
            $0.kind == .dangerLoss
                && $0.subjectReferences.contains("piece:white:knight:f3")
                && $0.integerValue == -3
        })
        XCTAssertTrue(request.chessEvidence.immediateReplies.contains {
            $0.replyMoveReference == ModelCoachingPositionEncoder.moveID(capture)
                && $0.capturedPieceReference == "piece:white:knight:f3"
                && $0.netMaterialGain == 3
        })
    }

    func testStagedMoveAndLearnerEventArePreservedWithoutCenterPolicy() {
        let stagedMove = Move(from: square("h2"), to: square("h4"))
        let stagedMoveID = ModelCoachingPositionEncoder.moveID(stagedMove)
        let snapshot = ModelCoachingSnapshot(
            coachingRequest: CoachingRequest(
                committedState: .startingPosition(),
                tentativeMove: stagedMove,
                learner: .white,
                positionRevision: 3,
                context: .tentativeMove(origin: .preexisting)
            ),
            interaction: CoachingInteractionSnapshot(
                selectedSquare: square("h2"),
                tentativeMove: stagedMove,
                positionRevision: 3
            ),
            latestEvent: ModelCoachingLearnerEvent(kind: .moveStaged, referencedIDs: [stagedMoveID]),
            currentTurnHistory: [],
            availableOperations: [.stageMove, .hint]
        )

        let request = ModelCoachingRequestBuilder.build(
            snapshot: snapshot,
            requestID: "request-staged",
            promptVersion: "prompt.v1"
        )

        XCTAssertEqual(request.currentInteraction.tentativeMoveReference, stagedMoveID)
        XCTAssertEqual(request.currentInteraction.latestEvent, snapshot.latestEvent)
        XCTAssertFalse(encodedJSON(for: request).contains("center"))
    }

    func testCheckerAndMateInOneFactsUseRuleAndEvaluatorSources() {
        let checkingState = state(
            sideToMove: .white,
            pieces: [
                square("e1"): Piece(kind: .king, color: .white),
                square("a8"): Piece(kind: .king, color: .black),
                square("e8"): Piece(kind: .rook, color: .black),
                square("b5"): Piece(kind: .bishop, color: .white),
            ]
        )
        let checkingRequest = ModelCoachingRequestBuilder.build(
            snapshot: makeSnapshot(state: checkingState),
            requestID: "request-check",
            promptVersion: "prompt.v1"
        )

        XCTAssertTrue(checkingRequest.chessEvidence.tacticalFacts.contains {
            $0.kind == .inCheck && $0.subjectReferences == ["piece:black:rook:e8"]
        })

        let castlingRequest = ModelCoachingRequestBuilder.build(
            snapshot: makeSnapshot(state: CoachingGoldenPosition.readyToCastle.state),
            requestID: "request-castle",
            promptVersion: "prompt.v1"
        )
        XCTAssertTrue(castlingRequest.chessEvidence.legalMoves.contains {
            $0.id == "move:e1-g1:castle-kingside" && $0.isLegal
        })

        let mateState = state(
            sideToMove: .white,
            pieces: [
                square("f6"): Piece(kind: .king, color: .white),
                square("g6"): Piece(kind: .queen, color: .white),
                square("h8"): Piece(kind: .king, color: .black),
            ]
        )
        let mateRequest = ModelCoachingRequestBuilder.build(
            snapshot: makeSnapshot(state: mateState),
            requestID: "request-mate",
            promptVersion: "prompt.v1"
        )

        XCTAssertTrue(mateRequest.chessEvidence.tacticalFacts.contains { $0.kind == .mateInOne })
    }

    func testHistoryOperationsAndJSONAreDeterministicAndPolicyFree() {
        var state = GameState.startingPosition()
        state.apply(Move(from: square("e2"), to: square("e4")))
        state.apply(Move(from: square("e7"), to: square("e5")))
        let history = [
            ModelCoachingHistoryEntry(
                sequence: 1,
                kind: .learnerEvent,
                summary: "help closed",
                referencedIDs: []
            ),
            ModelCoachingHistoryEntry(
                sequence: 2,
                kind: .learnerEvent,
                summary: "help reopened",
                referencedIDs: []
            ),
        ]
        let snapshot = makeSnapshot(
            state: state,
            history: history,
            operations: [.selectBoardPiece, .inspectSquare, .hint, .playMove, .closeHelp]
        )
        let first = ModelCoachingRequestBuilder.build(
            snapshot: snapshot,
            requestID: "request-one",
            promptVersion: "prompt.v1"
        )
        let second = ModelCoachingRequestBuilder.build(
            snapshot: snapshot,
            requestID: "request-two",
            promptVersion: "prompt.v1"
        )

        XCTAssertEqual(first.fullGameHistory.map(\.canonicalMove), ["e2e4", "e7e5"])
        XCTAssertEqual(first.fullGameHistory.map(\.displayNotation), ["e4", "e5"])
        XCTAssertEqual(first.currentTurnCoachingHistory, history)
        XCTAssertEqual(first.currentInteraction.availableOperationReferences, snapshot.availableOperations)
        XCTAssertEqual(
            encodedJSON(for: first).replacingOccurrences(of: "request-one", with: "request-two"),
            encodedJSON(for: second)
        )

        let json = encodedJSON(for: first)
        [
            "CoachingStage", "routine", "wakeTask", "preferred",
            "openingDevelopmentIsRelevant", "primaryDangerProblems",
            "LocalCoachingInsightSource", "Can you find", "Good choice"
        ].forEach { forbidden in
            XCTAssertFalse(json.contains(forbidden), "unexpected policy value: \(forbidden)")
        }
    }

    private func makeSnapshot(
        state: GameState,
        history: [ModelCoachingHistoryEntry] = [],
        operations: [ModelCoachingOperation] = [.selectBoardPiece, .inspectSquare, .stageMove]
    ) -> ModelCoachingSnapshot {
        ModelCoachingSnapshot(
            coachingRequest: CoachingRequest(
                committedState: state,
                tentativeMove: nil,
                learner: state.sideToMove,
                positionRevision: 1,
                context: .start
            ),
            interaction: CoachingInteractionSnapshot(
                selectedSquare: nil,
                tentativeMove: nil,
                positionRevision: 1
            ),
            latestEvent: ModelCoachingLearnerEvent(kind: .helpOpened, referencedIDs: []),
            currentTurnHistory: history,
            availableOperations: operations
        )
    }

    private func state(sideToMove: PieceColor, pieces: [Square: Piece]) -> GameState {
        GameState(board: Board(pieces: pieces), sideToMove: sideToMove)
    }

    private func encodedJSON(for request: ModelCoachingRequest) -> String {
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
