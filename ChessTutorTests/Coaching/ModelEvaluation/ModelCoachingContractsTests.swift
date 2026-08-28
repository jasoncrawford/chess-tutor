import Foundation
import XCTest
@testable import ChessTutor

final class ModelCoachingContractsTests: XCTestCase {
    func testRequestRoundTripsWithStableJSONShape() throws {
        let request = makeRequest()

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(ModelCoachingRequest.self, from: data)

        XCTAssertEqual(
            Set(object.keys),
            [
                "schemaVersion",
                "promptVersion",
                "requestID",
                "positionRevision",
                "currentPosition",
                "fullGameHistory",
                "currentInteraction",
                "currentTurnCoachingHistory",
                "chessEvidence",
                "permittedReferences"
            ]
        )
        XCTAssertEqual(object["schemaVersion"] as? String, "model-coaching-request.v1")
        XCTAssertEqual(decoded, request)
    }

    func testTurnRoundTripsWithStableJSONShape() throws {
        let turn = ModelCoachingTurn(
            schemaVersion: "model-coaching-turn.v1",
            requestID: "request-1",
            teachingIntent: .scanDanger,
            primaryMessage: "Look for pieces that could be taken.",
            instruction: "Tap the knight on e4.",
            responseToLatestAction: "Good choice.",
            actionReferences: ["action-hint"],
            boardTaskReference: "task-identify-piece",
            boardFocusReferences: ["piece-white-knight-e4"],
            relationshipReferences: ["relationship-knight-attacks-f6"],
            supportingEvidenceReferences: ["fact-danger-loss"]
        )

        let data = try JSONEncoder().encode(turn)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(ModelCoachingTurn.self, from: data)

        XCTAssertEqual(
            Set(object.keys),
            [
                "schemaVersion",
                "requestID",
                "teachingIntent",
                "primaryMessage",
                "instruction",
                "responseToLatestAction",
                "actionReferences",
                "boardTaskReference",
                "boardFocusReferences",
                "relationshipReferences",
                "supportingEvidenceReferences"
            ]
        )
        XCTAssertEqual(object["schemaVersion"] as? String, "model-coaching-turn.v1")
        XCTAssertEqual(decoded, turn)
    }

    func testCategoryEnumsEncodeTheirStableRawValues() {
        XCTAssertEqual([ModelCoachingEvidenceScopeKind.exhaustive, .bounded].map(\.rawValue), ["exhaustive", "bounded"])
        XCTAssertEqual([ModelCoachingRelationshipKind.attacks, .defends, .checks, .canCapture, .canRecapture].map(\.rawValue), ["attacks", "defends", "checks", "canCapture", "canRecapture"])
        XCTAssertEqual([ModelCoachingTacticalFactKind.inCheck, .checkmate, .stalemate, .dangerLoss, .exchangeGain, .mateInOne].map(\.rawValue), ["inCheck", "checkmate", "stalemate", "dangerLoss", "exchangeGain", "mateInOne"])
        XCTAssertEqual([ModelCoachingActionKind.hint, .noPieceNeedsHelp, .noSafeCapture, .looksSafe, .playMove, .tryAnotherMove, .closeHelp].map(\.rawValue), ["hint", "noPieceNeedsHelp", "noSafeCapture", "looksSafe", "playMove", "tryAnotherMove", "closeHelp"])
        XCTAssertEqual([ModelCoachingBoardTaskKind.none, .identifyPiece, .inspectRelationship, .movePiece, .confirmMove].map(\.rawValue), ["none", "identifyPiece", "inspectRelationship", "movePiece", "confirmMove"])
        XCTAssertEqual([ModelCoachingLearnerEventKind.helpOpened, .helpReopened, .pieceSelected, .squareInspected, .moveStaged, .moveReplaced, .moveRemoved, .actionChosen, .helpClosed].map(\.rawValue), ["helpOpened", "helpReopened", "pieceSelected", "squareInspected", "moveStaged", "moveReplaced", "moveRemoved", "actionChosen", "helpClosed"])
        XCTAssertEqual([ModelCoachingHistoryKind.learnerEvent, .tutorTurn, .supersededRequest].map(\.rawValue), ["learnerEvent", "tutorTurn", "supersededRequest"])
        XCTAssertEqual([ModelCoachingOperation.selectBoardPiece, .inspectSquare, .stageMove, .replaceMove, .removeMove, .hint, .noPieceNeedsHelp, .noSafeCapture, .looksSafe, .playMove, .tryAnotherMove, .closeHelp].map(\.rawValue), ["selectBoardPiece", "inspectSquare", "stageMove", "replaceMove", "removeMove", "hint", "noPieceNeedsHelp", "noSafeCapture", "looksSafe", "playMove", "tryAnotherMove", "closeHelp"])
        XCTAssertEqual([ModelCoachingTeachingIntent.orient, .scanDanger, .scanCapture, .chooseMove, .evaluateMove, .reviseMove, .confirmMove, .resolveCheck, .findMate, .other].map(\.rawValue), ["orient", "scanDanger", "scanCapture", "chooseMove", "evaluateMove", "reviseMove", "confirmMove", "resolveCheck", "findMate", "other"])
    }

    func testDefaultLimitsMatchTheContract() {
        XCTAssertEqual(
            ModelCoachingLimits.default,
            ModelCoachingLimits(
                primaryWords: 18,
                instructionWords: 14,
                responseWords: 16,
                actionTitleWords: 5,
                actionCount: 3
            )
        )
    }

    private func makeRequest() -> ModelCoachingRequest {
        ModelCoachingRequest(
            schemaVersion: "model-coaching-request.v1",
            promptVersion: "prompt.v1",
            requestID: "request-1",
            positionRevision: 7,
            currentPosition: ModelCoachingPosition(
                fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
                sideToMove: "white",
                status: "active"
            ),
            fullGameHistory: [
                ModelCoachingHistoryMove(ply: 1, canonicalMove: "e2e4", displayNotation: "e4")
            ],
            currentInteraction: ModelCoachingInteraction(
                selectedPieceReference: "piece-white-knight-e4",
                tentativeMoveReference: "move-knight-e4-f6",
                latestEvent: ModelCoachingLearnerEvent(
                    kind: .moveStaged,
                    referencedIDs: ["move-knight-e4-f6", "piece-white-knight-e4"]
                ),
                availableOperationReferences: [.inspectSquare, .stageMove, .hint]
            ),
            currentTurnCoachingHistory: [
                ModelCoachingHistoryEntry(
                    sequence: 1,
                    kind: .tutorTurn,
                    summary: "Notice the knight.",
                    referencedIDs: ["piece-white-knight-e4"]
                )
            ],
            chessEvidence: ModelCoachingEvidenceBundle(
                scope: ModelCoachingEvidenceScope(
                    legalMoves: .exhaustive,
                    relationships: .bounded,
                    immediateReplies: .bounded
                ),
                pieces: [
                    ModelCoachingPieceReference(
                        id: "piece-white-knight-e4",
                        color: "white",
                        kind: "knight",
                        square: "e4"
                    )
                ],
                legalMoves: [
                    ModelCoachingMoveReference(
                        id: "move-knight-e4-f6",
                        canonicalMove: "e4f6",
                        sourcePieceReference: "piece-white-knight-e4",
                        destinationSquare: "f6",
                        capturePieceReference: nil,
                        special: "none",
                        isLegal: true
                    )
                ],
                relationships: [
                    ModelCoachingRelationshipReference(
                        id: "relationship-knight-attacks-f6",
                        kind: .attacks,
                        sourceReference: "piece-white-knight-e4",
                        targetReference: "square-f6"
                    )
                ],
                immediateReplies: [
                    ModelCoachingReplyReference(
                        id: "reply-1",
                        afterMoveReference: "move-knight-e4-f6",
                        replyMoveReference: "move-black-king-e8-f7",
                        checkingPieceReferences: [],
                        capturedPieceReference: nil,
                        netMaterialGain: nil
                    )
                ],
                tacticalFacts: [
                    ModelCoachingTacticalFact(
                        id: "fact-danger-loss",
                        kind: .dangerLoss,
                        subjectReferences: ["piece-white-knight-e4"],
                        integerValue: -3
                    )
                ]
            ),
            permittedReferences: ModelCoachingPermittedReferences(
                actions: [
                    ModelCoachingPermittedAction(id: "action-hint", kind: .hint, title: "Show a hint")
                ],
                boardTasks: [
                    ModelCoachingPermittedBoardTask(id: "task-identify-piece", kind: .identifyPiece)
                ],
                boardFocus: ["piece-white-knight-e4"],
                relationships: ["relationship-knight-attacks-f6"],
                evidence: ["fact-danger-loss"]
            )
        )
    }
}
