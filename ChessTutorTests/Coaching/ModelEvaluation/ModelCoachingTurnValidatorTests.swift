import XCTest
@testable import ChessTutor

final class ModelCoachingTurnValidatorTests: XCTestCase {
    func testAcceptsValidTurn() {
        XCTAssertEqual(ModelCoachingTurnValidator.validate(makeTurn(), against: makeRequest()), [])
    }

    func testRejectsWrongTurnSchema() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(makeTurn(schemaVersion: "model-coaching-turn.v2"), against: makeRequest()),
            [.unsupportedTurnSchemaVersion]
        )
    }

    func testRejectsWrongRequestID() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(makeTurn(requestID: "request-2"), against: makeRequest()),
            [.requestIDMismatch]
        )
    }

    func testRejectsUnknownActionReference() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(makeTurn(actionReferences: ["action-unknown"]), against: makeRequest()),
            [.unknownActionReference("action-unknown")]
        )
    }

    func testRejectsUnknownBoardTaskReference() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(makeTurn(boardTaskReference: "task-unknown"), against: makeRequest()),
            [.unknownBoardTaskReference("task-unknown")]
        )
    }

    func testRejectsUnknownBoardFocusReference() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(makeTurn(boardFocusReferences: ["focus-unknown"]), against: makeRequest()),
            [.unknownBoardFocusReference("focus-unknown")]
        )
    }

    func testRejectsUnknownRelationshipReference() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(makeTurn(relationshipReferences: ["relationship-unknown"]), against: makeRequest()),
            [.unknownRelationshipReference("relationship-unknown")]
        )
    }

    func testRejectsUnknownSupportingEvidenceReference() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(makeTurn(supportingEvidenceReferences: ["evidence-unknown"]), against: makeRequest()),
            [.unknownSupportingEvidenceReference("evidence-unknown")]
        )
    }

    func testRejectsDuplicateActionReference() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(makeTurn(actionReferences: ["action-hint", "action-hint"]), against: makeRequest()),
            [.duplicateActionReference("action-hint")]
        )
    }

    func testRejectsMoreThanThreeActions() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(
                makeTurn(actionReferences: ["action-hint", "action-looks-safe", "action-play-move", "action-close-help"]),
                against: makeRequest()
            ),
            [.actionReferenceLimitExceeded]
        )
    }

    func testRejectsPrimaryMessageOverEighteenWords() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(
                makeTurn(primaryMessage: words(count: 19)),
                against: makeRequest()
            ),
            [.primaryMessageWordLimitExceeded]
        )
    }

    func testRejectsInstructionOverFourteenWords() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(
                makeTurn(instruction: words(count: 15)),
                against: makeRequest()
            ),
            [.instructionWordLimitExceeded]
        )
    }

    func testRejectsResponseOverSixteenWords() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(
                makeTurn(responseToLatestAction: words(count: 17)),
                against: makeRequest()
            ),
            [.responseWordLimitExceeded]
        )
    }

    func testRejectsActionTitleOverFiveWordsInRequest() {
        let request = makeRequest(actionTitle: words(count: 6))

        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(makeTurn(), against: request),
            [.actionTitleWordLimitExceeded("action-hint")]
        )
    }

    func testRejectsTurnWithoutSupportingEvidenceReference() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(makeTurn(supportingEvidenceReferences: []), against: makeRequest()),
            [.missingSupportingEvidenceReference]
        )
    }

    func testReturnsIssuesInDeterministicOrder() {
        XCTAssertEqual(
            ModelCoachingTurnValidator.validate(
                makeTurn(
                    schemaVersion: "model-coaching-turn.v2",
                    requestID: "request-2",
                    actionReferences: ["action-unknown", "action-unknown", "action-looks-safe", "action-play-move"],
                    boardFocusReferences: ["focus-unknown"],
                    supportingEvidenceReferences: []
                ),
                against: makeRequest()
            ),
            [
                .unsupportedTurnSchemaVersion,
                .requestIDMismatch,
                .unknownActionReference("action-unknown"),
                .duplicateActionReference("action-unknown"),
                .actionReferenceLimitExceeded,
                .unknownBoardFocusReference("focus-unknown"),
                .missingSupportingEvidenceReference
            ]
        )
    }

    private func makeRequest(actionTitle: String = "Show a hint") -> ModelCoachingRequest {
        ModelCoachingRequest(
            schemaVersion: "model-coaching-request.v1",
            promptVersion: "prompt.v1",
            requestID: "request-1",
            positionRevision: 7,
            currentPosition: ModelCoachingPosition(fen: "fen", sideToMove: "white", status: "active"),
            fullGameHistory: [],
            currentInteraction: ModelCoachingInteraction(
                selectedPieceReference: nil,
                tentativeMoveReference: nil,
                latestEvent: ModelCoachingLearnerEvent(kind: .helpOpened, referencedIDs: []),
                availableOperationReferences: [.hint]
            ),
            currentTurnCoachingHistory: [],
            chessEvidence: ModelCoachingEvidenceBundle(
                scope: ModelCoachingEvidenceScope(
                    legalMoves: .exhaustive,
                    relationships: .exhaustive,
                    immediateReplies: .exhaustive,
                    immediateRepliesDescription: "all legal opponent replies"
                ),
                pieces: [],
                legalMoves: [],
                relationships: [],
                immediateReplies: [],
                tacticalFacts: []
            ),
            permittedReferences: ModelCoachingPermittedReferences(
                actions: [
                    ModelCoachingPermittedAction(id: "action-hint", kind: .hint, title: actionTitle),
                    ModelCoachingPermittedAction(id: "action-looks-safe", kind: .looksSafe, title: "Looks safe"),
                    ModelCoachingPermittedAction(id: "action-play-move", kind: .playMove, title: "Play move"),
                    ModelCoachingPermittedAction(id: "action-close-help", kind: .closeHelp, title: "Close help")
                ],
                boardTasks: [
                    ModelCoachingPermittedBoardTask(id: "task-identify-piece", kind: .identifyPiece)
                ],
                boardFocus: ["focus-knight"],
                relationships: ["relationship-knight-attacks-f6"],
                evidence: ["evidence-legal-move"]
            )
        )
    }

    private func makeTurn(
        schemaVersion: String = "model-coaching-turn.v1",
        requestID: String = "request-1",
        primaryMessage: String = "Look at the knight.",
        instruction: String? = "Tap the knight.",
        responseToLatestAction: String? = "Good choice.",
        actionReferences: [String] = ["action-hint"],
        boardTaskReference: String? = "task-identify-piece",
        boardFocusReferences: [String] = ["focus-knight"],
        relationshipReferences: [String] = ["relationship-knight-attacks-f6"],
        supportingEvidenceReferences: [String] = ["evidence-legal-move"]
    ) -> ModelCoachingTurn {
        ModelCoachingTurn(
            schemaVersion: schemaVersion,
            requestID: requestID,
            teachingIntent: .scanDanger,
            primaryMessage: primaryMessage,
            instruction: instruction,
            responseToLatestAction: responseToLatestAction,
            actionReferences: actionReferences,
            boardTaskReference: boardTaskReference,
            boardFocusReferences: boardFocusReferences,
            relationshipReferences: relationshipReferences,
            supportingEvidenceReferences: supportingEvidenceReferences
        )
    }

    private func words(count: Int) -> String {
        (1...count).map { "word\($0)" }.joined(separator: " ")
    }
}
