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

    func testFenDerivesHalfmoveClockFromCommittedHistoryAndResetsIt() {
        var quietMoves = GameState.startingPosition()
        [
            Move(from: square("g1"), to: square("f3")),
            Move(from: square("g8"), to: square("f6")),
            Move(from: square("f3"), to: square("g1")),
            Move(from: square("f6"), to: square("g8")),
        ].forEach { quietMoves.apply($0) }

        XCTAssertEqual(fenField(4, for: quietMoves), "4")

        var pawnMove = GameState.startingPosition()
        [
            Move(from: square("g1"), to: square("f3")),
            Move(from: square("g8"), to: square("f6")),
            Move(from: square("e2"), to: square("e4")),
            Move(from: square("f6"), to: square("g8")),
        ].forEach { pawnMove.apply($0) }

        XCTAssertEqual(fenField(4, for: pawnMove), "1")

        var capture = GameState.startingPosition()
        [
            Move(from: square("e2"), to: square("e4")),
            Move(from: square("d7"), to: square("d5")),
            Move(from: square("e4"), to: square("d5")),
        ].forEach { capture.apply($0) }

        XCTAssertEqual(fenField(4, for: capture), "0")
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
        XCTAssertEqual(
            request.chessEvidence.scope.immediateRepliesDescription,
            "one legal opponent ply after each legal or staged learner move"
        )
        XCTAssertEqual(
            request.chessEvidence.pieces.map(\.id),
            request.chessEvidence.pieces.map(\.id).sorted()
        )
        XCTAssertEqual(
            request.chessEvidence.relationships.map(\.id),
            request.chessEvidence.relationships.map(\.id).sorted()
        )
        XCTAssertEqual(
            request.chessEvidence.immediateReplies.map(\.id),
            request.chessEvidence.immediateReplies.map(\.id).sorted()
        )
        XCTAssertEqual(
            request.chessEvidence.tacticalFacts.map(\.id),
            request.chessEvidence.tacticalFacts.map(\.id).sorted()
        )
        XCTAssertEqual(request.permittedReferences.boardFocus, request.permittedReferences.boardFocus.sorted())
        XCTAssertEqual(request.permittedReferences.relationships, request.permittedReferences.relationships.sorted())
        XCTAssertEqual(request.permittedReferences.evidence, request.permittedReferences.evidence.sorted())
        XCTAssertTrue(request.chessEvidence.relationships.contains {
            $0.id == "relationship:defend:piece:white:king:e1->piece:white:pawn:d2"
        })
        XCTAssertFalse(encodedJSON(for: request).contains("noPieceNeedsHelp"))
    }

    func testMoveConsequencesAndAbsenceFactsComeFromTheRealEvaluator() throws {
        let opening = request(for: .t1Entry)
        let safeKnight = try XCTUnwrap(opening.chessEvidence.moveConsequences.first {
            $0.moveReference == "move:g1-f3"
        })

        XCTAssertTrue(safeKnight.isLegal)
        XCTAssertEqual([], safeKnight.issueKinds)
        XCTAssertEqual([], safeKnight.criticalReplyReferences)
        XCTAssertEqual(0, safeKnight.worstEstimatedLoss)
        XCTAssertTrue(opening.chessEvidence.tacticalFacts.contains {
            $0.kind == .noImmediateDanger && $0.id == "fact:no-immediate-danger"
        })
        XCTAssertTrue(opening.chessEvidence.tacticalFacts.contains {
            $0.kind == .noUsefulSafeCapture && $0.id == "fact:no-useful-safe-capture"
        })
        XCTAssertTrue(opening.permittedReferences.evidence.contains("move:g1-f3"))

        let unsafeCapture = request(for: .t7UnsafeCapture)
        let bishopCapture = try XCTUnwrap(unsafeCapture.chessEvidence.moveConsequences.first {
            $0.moveReference == "move:c4-f7"
        })

        XCTAssertTrue(bishopCapture.isLegal)
        XCTAssertEqual([.materialLoss], bishopCapture.issueKinds)
        XCTAssertEqual(
            ["reply:move:c4-f7->move:g8-f7"],
            bishopCapture.criticalReplyReferences
        )
        XCTAssertEqual(3, bishopCapture.worstEstimatedLoss)
    }

    func testEveryMoveConsequenceReferencesDeclaredMoveAndMatchingReplies() {
        for evaluationCase in ModelCoachingEvaluationCorpus.allCases {
            let request = evaluationCase.request
            let moveIDs = Set(request.chessEvidence.legalMoves.map(\.id))
            let repliesByMove = Dictionary(grouping: request.chessEvidence.immediateReplies) {
                $0.afterMoveReference
            }

            for consequence in request.chessEvidence.moveConsequences {
                XCTAssertTrue(moveIDs.contains(consequence.moveReference), evaluationCase.id)
                XCTAssertLessThanOrEqual(consequence.criticalReplyReferences.count, 2, evaluationCase.id)
                XCTAssertEqual(
                    consequence.criticalReplyReferences,
                    consequence.criticalReplyReferences.sorted(),
                    evaluationCase.id
                )
                let matchingReplyIDs = Set((repliesByMove[consequence.moveReference] ?? []).map(\.id))
                XCTAssertTrue(
                    consequence.criticalReplyReferences.allSatisfy(matchingReplyIDs.contains),
                    evaluationCase.id
                )
            }
        }
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

    @MainActor
    func testStagedCaptureFromGameSessionKeepsDestinationSelectedButReferencesCommittedMover() async throws {
        let source = square("a1")
        let destination = square("a4")
        let capture = Move(from: source, to: destination)
        let committedState = state(
            sideToMove: .white,
            pieces: [
                square("e1"): Piece(kind: .king, color: .white),
                source: Piece(kind: .rook, color: .white),
                square("h8"): Piece(kind: .king, color: .black),
                destination: Piece(kind: .pawn, color: .black),
            ]
        )
        let advisor = ModelRequestRecordingAdvisor()
        let session = GameSession(state: committedState, coachingAdvisor: advisor)

        session.select(source)
        XCTAssertEqual(session.moveSelectedPiece(to: destination), .moved)
        XCTAssertEqual(session.selectedSquare, destination)
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        let recordedRequests = await advisor.recordedRequests()
        let coachingRequest = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(coachingRequest.committedState, committedState)
        XCTAssertEqual(coachingRequest.tentativeMove, capture)
        let snapshot = ModelCoachingSnapshot(
            coachingRequest: coachingRequest,
            interaction: CoachingInteractionSnapshot(
                selectedSquare: session.selectedSquare,
                tentativeMove: coachingRequest.tentativeMove,
                positionRevision: coachingRequest.positionRevision
            ),
            latestEvent: ModelCoachingLearnerEvent(
                kind: .moveStaged,
                referencedIDs: ["move:a1-a4"]
            ),
            currentTurnHistory: [],
            availableOperations: [.replaceMove, .removeMove, .playMove]
        )

        let request = ModelCoachingRequestBuilder.build(
            snapshot: snapshot,
            requestID: "request-session-capture",
            promptVersion: "prompt.v1"
        )

        XCTAssertEqual(session.selectedSquare, destination, "The physical-board UI keeps the moved piece selected")
        XCTAssertEqual(request.currentInteraction.tentativeMoveReference, "move:a1-a4")
        XCTAssertEqual(request.currentInteraction.selectedPieceReference, "piece:white:rook:a1")
    }

    func testDiscoveredCheckReplyUsesStationaryCommittedCheckerReference() throws {
        let learnerMove = Move(from: square("b1"), to: square("c3"))
        let replyMove = Move(from: square("e7"), to: square("c8"))
        let request = ModelCoachingRequestBuilder.build(
            snapshot: makeSnapshot(state: discoveredCheckReplyState()),
            requestID: "request-discovered-check",
            promptVersion: "prompt.v1"
        )

        let reply = try XCTUnwrap(request.chessEvidence.immediateReplies.first {
            $0.afterMoveReference == "move:b1-c3"
                && $0.replyMoveReference == "move:e7-c8"
        })
        XCTAssertEqual(reply.checkingPieceReferences, ["piece:black:rook:e8"])

        let afterReply = discoveredCheckReplyState()
            .applyingUnchecked(learnerMove)
            .applyingUnchecked(replyMove)
        XCTAssertEqual(
            LegalMoveGenerator.checkingPieceSquares(against: .white, in: afterReply.board),
            [square("e8")]
        )
    }

    func testCastlingCheckReplyUsesCommittedRookReference() throws {
        let learnerMove = Move(from: square("e1"), to: square("f1"))
        let replyMove = Move(
            from: square("e8"),
            to: square("g8"),
            special: .castleKingside
        )
        let request = ModelCoachingRequestBuilder.build(
            snapshot: makeSnapshot(state: castlingCheckReplyState()),
            requestID: "request-castling-check",
            promptVersion: "prompt.v1"
        )

        let reply = try XCTUnwrap(request.chessEvidence.immediateReplies.first {
            $0.afterMoveReference == "move:e1-f1"
                && $0.replyMoveReference == "move:e8-g8:castle-kingside"
        })
        XCTAssertEqual(reply.checkingPieceReferences, ["piece:black:rook:h8"])

        let afterReply = castlingCheckReplyState()
            .applyingUnchecked(learnerMove)
            .applyingUnchecked(replyMove)
        XCTAssertEqual(
            LegalMoveGenerator.checkingPieceSquares(against: .white, in: afterReply.board),
            [square("f8")]
        )
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

    func testReplyCheckersResolveToDeclaredCommittedPieceReferences() throws {
        let state = state(
            sideToMove: .white,
            pieces: [
                square("e1"): Piece(kind: .king, color: .white),
                square("g1"): Piece(kind: .knight, color: .white),
                square("h8"): Piece(kind: .king, color: .black),
                square("a8"): Piece(kind: .rook, color: .black),
            ]
        )
        let request = ModelCoachingRequestBuilder.build(
            snapshot: makeSnapshot(state: state),
            requestID: "request-reply-check",
            promptVersion: "prompt.v1"
        )
        let declaredPieceIDs = Set(request.chessEvidence.pieces.map(\.id))
        let checkingReply = try XCTUnwrap(request.chessEvidence.immediateReplies.first {
            $0.afterMoveReference == "move:g1-f3" && $0.replyMoveReference == "move:a8-e8"
        })

        XCTAssertEqual(checkingReply.checkingPieceReferences, ["piece:black:rook:a8"])
        XCTAssertTrue(
            request.chessEvidence.immediateReplies.flatMap(\.checkingPieceReferences)
                .allSatisfy(declaredPieceIDs.contains)
        )
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

    private func request(for goldenCase: CoachingGoldenCase) -> ModelCoachingRequest {
        ModelCoachingEvaluationCorpus.allCases.first {
            $0.id == goldenCase.rawValue
        }!.request
    }

    private func state(sideToMove: PieceColor, pieces: [Square: Piece]) -> GameState {
        GameState(board: Board(pieces: pieces), sideToMove: sideToMove)
    }

    private func discoveredCheckReplyState() -> GameState {
        state(
            sideToMove: .white,
            pieces: [
                square("e1"): Piece(kind: .king, color: .white),
                square("b1"): Piece(kind: .knight, color: .white),
                square("h8"): Piece(kind: .king, color: .black),
                square("e8"): Piece(kind: .rook, color: .black),
                square("e7"): Piece(kind: .knight, color: .black),
            ]
        )
    }

    private func castlingCheckReplyState() -> GameState {
        GameState(
            board: Board(pieces: [
                square("e1"): Piece(kind: .king, color: .white),
                square("e8"): Piece(kind: .king, color: .black),
                square("h8"): Piece(kind: .rook, color: .black),
            ]),
            sideToMove: .white,
            castlingRights: CastlingRights(blackKingside: true)
        )
    }

    private func encodedJSON(for request: ModelCoachingRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try! encoder.encode(request), encoding: .utf8)!
    }

    private func fenField(_ index: Int, for state: GameState) -> String {
        String(ModelCoachingPositionEncoder.fen(for: state).split(separator: " ")[index])
    }

    private func square(_ algebraic: String) -> Square {
        let characters = Array(algebraic.utf8)
        return Square(
            file: Square.File(rawValue: Int(characters[0]) - 96)!,
            rank: Int(String(UnicodeScalar(characters[1])))!
        )
    }
}

private actor ModelRequestRecordingAdvisor: CoachingAdvising {
    private var requests: [CoachingRequest] = []

    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        requests.append(request)
        return try await LocalCoachingAdvisor().advice(for: request)
    }

    func recordedRequests() -> [CoachingRequest] {
        requests
    }
}
