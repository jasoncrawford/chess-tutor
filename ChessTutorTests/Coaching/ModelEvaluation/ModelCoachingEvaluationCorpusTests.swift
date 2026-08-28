import XCTest
@testable import ChessTutor

final class ModelCoachingEvaluationCorpusTests: XCTestCase {
    func testCorpusContainsEveryGoldenCaseExactlyOnceWithReservedHiddenSplit() throws {
        let cases = ModelCoachingEvaluationCorpus.allCases
        let expectedIDs = Set(CoachingGoldenCase.allCases.map(\.rawValue))
        let expectedHiddenIDs: Set<String> = [
            "t1OutsidePawnMove",
            "t3WrongAttacker",
            "t4LowerPriorityPawn",
            "t5ProtectedAbsence",
            "t7UnsafeCapture",
            "t9Completed",
            "t10Completed",
            "t11IncorrectLooksSafe",
            "t11BenignCaptureLooksSafe",
            "t12WrongChecker",
            "t12UnsupportedSafeMove",
        ]

        XCTAssertEqual(cases.count, 52)
        XCTAssertEqual(Set(cases.map(\.id)), expectedIDs)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count)
        XCTAssertEqual(ModelCoachingEvaluationCorpus.visibleCases.count, 41)
        XCTAssertEqual(ModelCoachingEvaluationCorpus.hiddenCases.count, 11)
        XCTAssertEqual(Set(ModelCoachingEvaluationCorpus.hiddenCases.map(\.id)), expectedHiddenIDs)
        XCTAssertEqual(
            Double(ModelCoachingEvaluationCorpus.hiddenCases.count) / Double(cases.count) * 100,
            21.15,
            accuracy: 0.01
        )
        XCTAssertTrue(ModelCoachingEvaluationCorpus.visibleCases.allSatisfy { $0.split == .visible })
        XCTAssertTrue(ModelCoachingEvaluationCorpus.hiddenCases.allSatisfy { $0.split == .hidden })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(cases)
        XCTAssertEqual(try JSONDecoder().decode([ModelCoachingEvaluationCase].self, from: data), cases)
    }

    func testEverySemanticOracleIsConcreteAndCarriesSharedSafetyProhibitions() {
        let sharedProhibitions = [
            "evaluator",
            "debugger",
            "invented board facts",
            "unanswerable question",
            "repeated feedback",
            "obsolete step",
        ]

        for evaluationCase in ModelCoachingEvaluationCorpus.allCases {
            let oracle = evaluationCase.oracle
            XCTAssertGreaterThanOrEqual(
                oracle.successCriteria.count,
                2,
                "\(evaluationCase.id) needs at least two success criteria"
            )
            XCTAssertFalse(
                oracle.successCriteria.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                "\(evaluationCase.id) has an empty success criterion"
            )
            XCTAssertGreaterThanOrEqual(
                oracle.severeFailureCriteria.count,
                1,
                "\(evaluationCase.id) needs a severe-failure criterion"
            )
            XCTAssertFalse(
                oracle.permittedTeachingIntents.isEmpty,
                "\(evaluationCase.id) needs a permitted teaching intent"
            )
            let prohibited = oracle.prohibitedPhrases.map { $0.lowercased() }
            for phrase in sharedProhibitions {
                XCTAssertTrue(
                    prohibited.contains(where: { $0.contains(phrase) }),
                    "\(evaluationCase.id) is missing shared prohibition \(phrase)"
                )
            }
        }
    }

    func testHiddenCaseIDsDoNotAppearInPromptExamples() throws {
        let examplesURL = repositoryRoot
            .appendingPathComponent("Tools/CoachingEval/prompts/examples-v1.json")
        let examples = FileManager.default.fileExists(atPath: examplesURL.path)
            ? try String(contentsOf: examplesURL, encoding: .utf8)
            : ""

        for hiddenCase in ModelCoachingEvaluationCorpus.hiddenCases {
            XCTAssertFalse(examples.contains(hiddenCase.id), "Prompt examples exposed \(hiddenCase.id)")
        }
    }

    func testEveryRequestHasClosedPermittedSetsAndCoherentOracleReferences() {
        for evaluationCase in ModelCoachingEvaluationCorpus.allCases {
            let request = evaluationCase.request
            let permitted = request.permittedReferences
            let evidenceIDs = Set(
                request.chessEvidence.immediateReplies.map(\.id)
                    + request.chessEvidence.tacticalFacts.map(\.id)
            )

            XCTAssertEqual(
                permitted.boardFocus,
                request.chessEvidence.pieces.map(\.id).sorted(),
                evaluationCase.id
            )
            XCTAssertEqual(
                permitted.relationships,
                request.chessEvidence.relationships.map(\.id).sorted(),
                evaluationCase.id
            )
            XCTAssertEqual(permitted.evidence, evidenceIDs.sorted(), evaluationCase.id)
            XCTAssertEqual(
                permitted.actions.map(\.kind.rawValue),
                request.currentInteraction.availableOperationReferences.compactMap { actionKind(for: $0) }.map(\.rawValue),
                evaluationCase.id
            )
            XCTAssertEqual(
                permitted.boardTasks.map(\.kind.rawValue),
                request.currentInteraction.availableOperationReferences.compactMap { boardTaskKind(for: $0) }.map(\.rawValue),
                evaluationCase.id
            )

            let oracle = evaluationCase.oracle
            let allOracleEvidence = oracle.requiredEvidenceReferences
                + oracle.requiredAnyEvidenceReferenceGroups.flatMap { $0 }
                + oracle.forbiddenEvidenceReferences
            XCTAssertTrue(
                allOracleEvidence.allSatisfy(evidenceIDs.contains),
                "\(evaluationCase.id) has an oracle reference absent from its request: \(Set(allOracleEvidence).subtracting(evidenceIDs))"
            )
            XCTAssertTrue(
                Set(oracle.requiredEvidenceReferences).isDisjoint(with: oracle.forbiddenEvidenceReferences),
                evaluationCase.id
            )
            for group in oracle.requiredAnyEvidenceReferenceGroups {
                XCTAssertFalse(group.isEmpty, "\(evaluationCase.id) has an empty any-evidence group")
            }

            let permittedActionKinds = Set(permitted.actions.map(\.kind.rawValue))
            XCTAssertTrue(
                oracle.requiredActionKinds.allSatisfy(permittedActionKinds.contains),
                "\(evaluationCase.id) requires an unavailable action"
            )
            XCTAssertTrue(
                Set(oracle.forbiddenActionKinds).isDisjoint(with: permittedActionKinds),
                "\(evaluationCase.id) permits a forbidden action"
            )
        }
    }

    func testRelationshipsAndMovesAreDerivableFromEncodedPositions() throws {
        for evaluationCase in ModelCoachingEvaluationCorpus.allCases {
            let request = evaluationCase.request
            let state = CoachingFENParser.parse(request.currentPosition.fen)
            let piecesByID = Dictionary(uniqueKeysWithValues: request.chessEvidence.pieces.map { ($0.id, $0) })

            for relationship in request.chessEvidence.relationships {
                let source = try XCTUnwrap(piecesByID[relationship.sourceReference], evaluationCase.id)
                let target = try XCTUnwrap(piecesByID[relationship.targetReference], evaluationCase.id)
                let sourceSquare = sq(source.square)
                let targetSquare = sq(target.square)
                XCTAssertTrue(
                    LegalMoveGenerator.controlledSquares(from: sourceSquare, in: state).contains(targetSquare),
                    "\(evaluationCase.id) cannot derive \(relationship.id)"
                )
                switch relationship.kind {
                case .attacks:
                    XCTAssertNotEqual(source.color, target.color, evaluationCase.id)
                case .defends:
                    XCTAssertEqual(source.color, target.color, evaluationCase.id)
                case .checks:
                    XCTAssertNotEqual(source.color, target.color, evaluationCase.id)
                    XCTAssertEqual(target.kind, Piece.Kind.king.rawValue, evaluationCase.id)
                case .canCapture, .canRecapture:
                    XCTFail("The exhaustive board relationship encoder must not synthesize \(relationship.kind)")
                }
            }

            let allowedMoves = state.board.pieces.keys.flatMap {
                LegalMoveGenerator.allowedMoves(for: $0, by: state.sideToMove, in: state)
            }
            let allowedByID = Dictionary(
                uniqueKeysWithValues: allowedMoves.map { (ModelCoachingPositionEncoder.moveID($0), $0) }
            )
            let legalIDs = Set(state.board.pieces.keys.flatMap {
                LegalMoveGenerator.legalMoves(for: $0, by: state.sideToMove, in: state)
            }.map(ModelCoachingPositionEncoder.moveID))
            let tentativeID = request.currentInteraction.tentativeMoveReference
            let expectedMoveIDs = Set(allowedByID.keys).union(tentativeID.map { [$0] } ?? [])

            XCTAssertEqual(Set(request.chessEvidence.legalMoves.map(\.id)), expectedMoveIDs, evaluationCase.id)
            for moveReference in request.chessEvidence.legalMoves {
                XCTAssertEqual(moveReference.isLegal, legalIDs.contains(moveReference.id), evaluationCase.id)
                XCTAssertNotNil(
                    allowedByID[moveReference.id],
                    "\(evaluationCase.id) contains a staged move outside inherent movement: \(moveReference.id)"
                )
            }

            for replyReference in request.chessEvidence.immediateReplies {
                let learnerMove = try XCTUnwrap(allowedByID[replyReference.afterMoveReference], evaluationCase.id)
                let afterMove = state.applyingUnchecked(learnerMove)
                let legalReplyIDs = Set(
                    LegalMoveGenerator.allLegalMoves(in: afterMove).map(ModelCoachingPositionEncoder.moveID)
                )
                XCTAssertTrue(
                    legalReplyIDs.contains(replyReference.replyMoveReference),
                    "\(evaluationCase.id) has an illegal reply \(replyReference.id)"
                )
            }
        }
    }

    func testHistoriesPreserveCallerOrderAndMatchLatestInteraction() throws {
        for evaluationCase in ModelCoachingEvaluationCorpus.allCases {
            let request = evaluationCase.request
            XCTAssertEqual(
                request.fullGameHistory.map(\.ply),
                request.fullGameHistory.indices.map { $0 + 1 },
                evaluationCase.id
            )
            XCTAssertEqual(
                request.currentTurnCoachingHistory.map(\.sequence),
                request.currentTurnCoachingHistory.indices.map { $0 + 1 },
                evaluationCase.id
            )
            let finalHistory = try XCTUnwrap(request.currentTurnCoachingHistory.last, evaluationCase.id)
            XCTAssertEqual(finalHistory.kind, .learnerEvent, evaluationCase.id)
            XCTAssertEqual(finalHistory.referencedIDs, request.currentInteraction.latestEvent.referencedIDs, evaluationCase.id)
            XCTAssertTrue(
                finalHistory.summary.hasSuffix(request.currentInteraction.latestEvent.kind.rawValue),
                evaluationCase.id
            )
            if request.currentInteraction.latestEvent.kind == .pieceSelected {
                XCTAssertEqual(
                    request.currentInteraction.selectedPieceReference,
                    request.currentInteraction.latestEvent.referencedIDs.first,
                    evaluationCase.id
                )
            }
            if request.currentInteraction.latestEvent.kind == .moveStaged
                || request.currentInteraction.latestEvent.kind == .moveReplaced {
                XCTAssertEqual(
                    request.currentInteraction.tentativeMoveReference,
                    request.currentInteraction.latestEvent.referencedIDs.first,
                    evaluationCase.id
                )
            }
        }

        let wrongAttacker = try XCTUnwrap(
            ModelCoachingEvaluationCorpus.allCases.first { $0.id == "t3WrongAttacker" }
        )
        XCTAssertEqual(
            wrongAttacker.request.currentTurnCoachingHistory.flatMap(\.referencedIDs),
            ["piece:white:knight:f3", "piece:black:king:g8"]
        )
        let unsafeBishop = try XCTUnwrap(
            ModelCoachingEvaluationCorpus.allCases.first { $0.id == "t11UnsafeBishopEntry" }
        )
        XCTAssertEqual(unsafeBishop.request.fullGameHistory.map(\.canonicalMove), ["e2e4", "e7e6"])
    }

    func testCorpusEncodingIsDeterministicAndRequestsContainNoOracleOrLegacyPolicy() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(ModelCoachingEvaluationCorpus.allCases)
        let second = try encoder.encode(ModelCoachingEvaluationCorpus.allCases)

        XCTAssertEqual(normalizingRequestIDs(first), normalizingRequestIDs(second))

        let requestJSON = try ModelCoachingEvaluationCorpus.allCases.map {
            String(decoding: try encoder.encode($0.request), as: UTF8.self)
        }.joined(separator: "\n")
        [
            "CoachingStage", "routine", "wakeTask", "preferred",
            "openingDevelopmentIsRelevant", "primaryDangerProblems",
            "LocalCoachingInsightSource", "LocalCoachingAdvisor",
            "CoachingReconciler", "CoachingPresentationProjector",
            "LocalCoachingExplanationSource", "successCriteria",
            "severeFailureCriteria", "prohibitedPhrases",
            "Can you find", "Good choice",
        ].forEach { forbidden in
            XCTAssertFalse(requestJSON.contains(forbidden), "Requests leaked \(forbidden)")
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func actionKind(for operation: ModelCoachingOperation) -> ModelCoachingActionKind? {
        switch operation {
        case .hint: .hint
        case .noPieceNeedsHelp: .noPieceNeedsHelp
        case .noSafeCapture: .noSafeCapture
        case .looksSafe: .looksSafe
        case .playMove: .playMove
        case .tryAnotherMove: .tryAnotherMove
        case .closeHelp: .closeHelp
        case .selectBoardPiece, .inspectSquare, .stageMove, .replaceMove, .removeMove: nil
        }
    }

    private func boardTaskKind(for operation: ModelCoachingOperation) -> ModelCoachingBoardTaskKind? {
        switch operation {
        case .selectBoardPiece: .identifyPiece
        case .inspectSquare: .inspectRelationship
        case .stageMove, .replaceMove, .removeMove: .movePiece
        case .playMove: .confirmMove
        case .hint, .noPieceNeedsHelp, .noSafeCapture, .looksSafe, .tryAnotherMove, .closeHelp: nil
        }
    }

    private func normalizingRequestIDs(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).replacingOccurrences(
            of: #""requestID":"[^"]+""#,
            with: #""requestID":"normalized""#,
            options: .regularExpression
        )
    }
}
