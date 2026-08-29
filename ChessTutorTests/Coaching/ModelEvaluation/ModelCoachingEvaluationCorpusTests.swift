import CryptoKit
import XCTest
@testable import ChessTutor

final class ModelCoachingEvaluationCorpusTests: XCTestCase {
    func testEveryCaseCarriesTheVersionedReproducibleCompactContext() throws {
        let cases = ModelCoachingEvaluationCorpus.allCases

        XCTAssertEqual(cases.count, 52)
        XCTAssertEqual(cases.map(\.id), CoachingGoldenCase.allCases.map(\.rawValue))
        XCTAssertEqual(cases.filter { $0.split == .visible }.count, 41)
        XCTAssertEqual(cases.filter { $0.split == .hidden }.count, 11)

        for evaluationCase in cases {
            let request = evaluationCase.request
            let compact = evaluationCase.compactContext
            let rebuilt = try ModelCoachingContextCompiler.compile(
                request,
                promptVersion: "tutor-v3"
            )

            XCTAssertEqual(compact, rebuilt, evaluationCase.id)
            XCTAssertEqual(compact.schemaVersion, "model-coaching-context.v1", evaluationCase.id)
            XCTAssertEqual(compact.promptVersion, "tutor-v3", evaluationCase.id)
            XCTAssertEqual(compact.requestID, request.requestID, evaluationCase.id)
            XCTAssertEqual(compact.positionRevision, request.positionRevision, evaluationCase.id)
            XCTAssertFalse(compact.markdown.isEmpty, evaluationCase.id)
            XCTAssertFalse(compact.referenceBindings.isEmpty, evaluationCase.id)
            XCTAssertEqual(
                sourceReferences(in: request),
                Set(compact.referenceBindings.map(\.stableID))
                    .union(compact.omissions.map(\.stableID)),
                evaluationCase.id
            )
            XCTAssertTrue(
                Set(compact.referenceBindings.map(\.stableID))
                    .isDisjoint(with: compact.omissions.map(\.stableID)),
                evaluationCase.id
            )
        }
    }

    func testCompactContextContainsCurrentMechanicsWithoutSmuggledPolicy() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for evaluationCase in ModelCoachingEvaluationCorpus.allCases {
            let compact = evaluationCase.compactContext
            let markdown = compact.markdown
            let boundAliases = Set(compact.referenceBindings.map(\.alias))
            let aliasesInMarkdown = aliasTokens(in: markdown)

            XCTAssertTrue(markdown.contains(evaluationCase.request.currentPosition.fen), evaluationCase.id)
            XCTAssertTrue(
                markdown.contains(evaluationCase.request.currentInteraction.latestEvent.kind.rawValue),
                evaluationCase.id
            )
            XCTAssertTrue(aliasesInMarkdown.isSubset(of: boundAliases), evaluationCase.id)
            XCTAssertFalse(markdown.contains("CoachingStage"), evaluationCase.id)
            XCTAssertFalse(markdown.contains("CoachingPresentation"), evaluationCase.id)
            for criterion in evaluationCase.oracle.successCriteria
                + evaluationCase.oracle.severeFailureCriteria {
                XCTAssertFalse(markdown.contains(criterion), evaluationCase.id)
            }

            let requestHash = sha256(try encoder.encode(evaluationCase.request))
            let rebuiltRequestHash = sha256(try encoder.encode(evaluationCase.request))
            let compactHash = sha256(try encoder.encode(compact))
            let rebuiltCompactHash = sha256(
                try encoder.encode(ModelCoachingContextCompiler.compile(
                    evaluationCase.request,
                    promptVersion: "tutor-v3"
                ))
            )
            XCTAssertEqual(requestHash, rebuiltRequestHash, evaluationCase.id)
            XCTAssertEqual(compactHash, rebuiltCompactHash, evaluationCase.id)
        }
    }

    func testFirstMoveOracleDoesNotRequireNoPieceNeedsHelpAction() throws {
        let firstMove = try XCTUnwrap(
            ModelCoachingEvaluationCorpus.visibleCases.first { $0.id == "t1Entry" }
        )

        XCTAssertFalse(firstMove.oracle.requiredActionKinds.contains("noPieceNeedsHelp"))
    }

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

    func testCorpusContainsRequiredInteractionStressKinds() throws {
        let casesByID = Dictionary(
            uniqueKeysWithValues: ModelCoachingEvaluationCorpus.allCases.map { ($0.id, $0) }
        )

        let replacement = try XCTUnwrap(casesByID["t11Safe"])
        XCTAssertEqual(replacement.split, .visible)
        XCTAssertEqual(replacement.request.currentInteraction.latestEvent.kind, .moveReplaced)
        XCTAssertEqual(replacement.request.currentInteraction.latestEvent.referencedIDs, ["move:g1-f3"])

        let removal = try XCTUnwrap(casesByID["t11UnsafeBishopFound"])
        XCTAssertEqual(removal.request.currentInteraction.latestEvent.kind, .moveRemoved)
        XCTAssertEqual(removal.request.currentInteraction.latestEvent.referencedIDs, ["move:f1-a6"])
        XCTAssertNil(removal.request.currentInteraction.tentativeMoveReference)

        let reopened = try XCTUnwrap(casesByID["t12UnsupportedEntry"])
        XCTAssertEqual(reopened.request.currentInteraction.latestEvent.kind, .helpReopened)
        XCTAssertEqual(
            reopened.request.currentTurnCoachingHistory.map(\.kind),
            [.learnerEvent, .tutorTurn, .learnerEvent, .supersededRequest, .learnerEvent]
        )
        XCTAssertEqual(
            reopened.request.currentTurnCoachingHistory.map(\.summary),
            [
                "learner event: helpOpened",
                "tutor turn: quiet-position guidance displayed",
                "learner event: helpClosed",
                "superseded request: help panel closed",
                "learner event: helpReopened",
            ]
        )

        XCTAssertEqual(
            Set(ModelCoachingEvaluationCorpus.allCases.flatMap(\.request.currentTurnCoachingHistory).map(\.kind)),
            [.learnerEvent, .tutorTurn, .supersededRequest]
        )
    }

    func testVisibleCorpusProvidesReplacementAndMateInOneExampleInputs() {
        let visibleCases = ModelCoachingEvaluationCorpus.visibleCases
        XCTAssertEqual(
            visibleCases.filter { $0.request.currentInteraction.latestEvent.kind == .moveReplaced }.map(\.id),
            ["t11Safe"]
        )
        XCTAssertEqual(
            visibleCases.filter {
                $0.request.chessEvidence.tacticalFacts.contains { $0.kind == .mateInOne }
            }.map(\.id),
            ["t9Hint"]
        )
        XCTAssertTrue(
            visibleCases.first { $0.id == "t9Hint" }?.request.chessEvidence.tacticalFacts.contains {
                $0.id == "fact:mate-in-one:move:g6-g7"
                    && $0.subjectReferences == ["move:g6-g7"]
            } == true
        )
    }

    func testCorpusBindsMechanicallyDerivedDiscoveredAndCastlingCheckReplies() throws {
        let casesByID = Dictionary(
            uniqueKeysWithValues: ModelCoachingEvaluationCorpus.allCases.map { ($0.id, $0) }
        )

        let discovered = try XCTUnwrap(casesByID["t11HarmlessCheck"])
        let discoveredReplyID = "reply:move:b1-c3->move:e7-c8"
        let discoveredReply = try XCTUnwrap(
            discovered.request.chessEvidence.immediateReplies.first { $0.id == discoveredReplyID }
        )
        XCTAssertEqual(discovered.split, .visible)
        XCTAssertEqual(discoveredReply.checkingPieceReferences, ["piece:black:rook:e8"])
        XCTAssertTrue(discovered.oracle.requiredEvidenceReferences.contains(discoveredReplyID))
        let discoveredState = CoachingFENParser.parse(discovered.request.currentPosition.fen)
            .applyingUnchecked(Move(from: sq("b1"), to: sq("c3")))
            .applyingUnchecked(Move(from: sq("e7"), to: sq("c8")))
        XCTAssertEqual(
            LegalMoveGenerator.checkingPieceSquares(against: .white, in: discoveredState.board),
            [sq("e8")]
        )

        let castling = try XCTUnwrap(casesByID["t2OneSquareKingMove"])
        let castlingReplyID = "reply:move:e1-f1->move:e8-g8:castle-kingside"
        let castlingReply = try XCTUnwrap(
            castling.request.chessEvidence.immediateReplies.first { $0.id == castlingReplyID }
        )
        XCTAssertEqual(castling.split, .visible)
        XCTAssertEqual(castlingReply.checkingPieceReferences, ["piece:black:rook:h8"])
        XCTAssertTrue(castling.oracle.requiredEvidenceReferences.contains(castlingReplyID))
        let castlingState = CoachingFENParser.parse(castling.request.currentPosition.fen)
            .applyingUnchecked(Move(from: sq("e1"), to: sq("f1")))
            .applyingUnchecked(Move(
                from: sq("e8"),
                to: sq("g8"),
                special: .castleKingside
            ))
        XCTAssertEqual(
            LegalMoveGenerator.checkingPieceSquares(against: .white, in: castlingState.board),
            [sq("f8")]
        )
    }

    func testLongAndShortHistoryPairSharesCurrentAdviceContract() throws {
        let casesByID = Dictionary(
            uniqueKeysWithValues: ModelCoachingEvaluationCorpus.allCases.map { ($0.id, $0) }
        )
        let short = try XCTUnwrap(casesByID["t9Entry"])
        let long = try XCTUnwrap(casesByID["t10Entry"])

        XCTAssertEqual(short.split, .visible)
        XCTAssertEqual(long.split, .visible)
        XCTAssertEqual(short.request.fullGameHistory.count, 0)
        XCTAssertEqual(long.request.fullGameHistory.count, 8)
        XCTAssertNotEqual(short.request.fullGameHistory, long.request.fullGameHistory)
        XCTAssertEqual(
            authoritativeFENFields(short.request.currentPosition.fen),
            authoritativeFENFields(long.request.currentPosition.fen)
        )
        XCTAssertEqual(short.request.currentPosition.sideToMove, long.request.currentPosition.sideToMove)
        XCTAssertEqual(short.request.currentPosition.status, long.request.currentPosition.status)
        XCTAssertEqual(short.request.positionRevision, long.request.positionRevision)
        XCTAssertEqual(short.request.currentInteraction, long.request.currentInteraction)
        XCTAssertEqual(short.request.currentTurnCoachingHistory, long.request.currentTurnCoachingHistory)
        XCTAssertEqual(short.request.chessEvidence, long.request.chessEvidence)
        XCTAssertEqual(short.request.permittedReferences, long.request.permittedReferences)
        XCTAssertEqual(short.oracle, long.oracle)
    }

    func testLongHistoryPairReturnsToCurrentPositionOnlyOnceWithoutThreefoldClaim() throws {
        let casesByID = Dictionary(
            uniqueKeysWithValues: ModelCoachingEvaluationCorpus.allCases.map { ($0.id, $0) }
        )
        let short = try XCTUnwrap(casesByID["t9Entry"])
        let long = try XCTUnwrap(casesByID["t10Entry"])
        let initialState = CoachingGoldenPosition.createRookThreat.state
        let shortReplay = try replay(short.request.fullGameHistory, from: initialState)
        let longReplay = try replay(long.request.fullGameHistory, from: initialState)
        let currentPositionKey = repetitionKey(for: initialState)

        XCTAssertEqual(shortReplay.repetitionCounts, [currentPositionKey: 1])
        XCTAssertEqual(long.request.fullGameHistory.count, 8)
        XCTAssertEqual(longReplay.repetitionCounts[currentPositionKey], 2)
        XCTAssertEqual(longReplay.repetitionCounts.count, 8)
        XCTAssertEqual(longReplay.repetitionCounts.values.max(), 2)
        XCTAssertFalse(longReplay.repetitionCounts.values.contains { $0 >= 3 })

        XCTAssertEqual(shortReplay.finalState.board, initialState.board)
        XCTAssertEqual(longReplay.finalState.board, initialState.board)
        XCTAssertEqual(shortReplay.finalState.sideToMove, initialState.sideToMove)
        XCTAssertEqual(longReplay.finalState.sideToMove, initialState.sideToMove)
        XCTAssertEqual(shortReplay.finalState.castlingRights, initialState.castlingRights)
        XCTAssertEqual(longReplay.finalState.castlingRights, initialState.castlingRights)
        XCTAssertEqual(shortReplay.finalState.enPassantTarget, initialState.enPassantTarget)
        XCTAssertEqual(longReplay.finalState.enPassantTarget, initialState.enPassantTarget)
        XCTAssertEqual(shortReplay.finalState.result, .ongoing)
        XCTAssertEqual(longReplay.finalState.result, .ongoing)
        XCTAssertEqual(short.request.currentPosition.status, "active")
        XCTAssertEqual(long.request.currentPosition.status, "active")
    }

    func testNoSafeCaptureCaseFollowsLearnerOrdinaryStagedMoveAhead() throws {
        let evaluationCase = try XCTUnwrap(
            ModelCoachingEvaluationCorpus.visibleCases.first { $0.id == "t7NoSafeCapture" }
        )
        let request = evaluationCase.request

        XCTAssertEqual(request.currentInteraction.latestEvent.kind, .moveStaged)
        XCTAssertEqual(request.currentInteraction.latestEvent.referencedIDs, ["move:c4-d3"])
        XCTAssertEqual(request.currentInteraction.tentativeMoveReference, "move:c4-d3")
        XCTAssertEqual(request.currentInteraction.selectedPieceReference, "piece:white:bishop:c4")
        XCTAssertEqual(
            request.currentTurnCoachingHistory.map(\.kind),
            [.learnerEvent, .learnerEvent, .tutorTurn, .learnerEvent]
        )
        XCTAssertEqual(
            request.currentTurnCoachingHistory.map(\.referencedIDs),
            [[], ["action:noSafeCapture"], [], ["move:c4-d3"]]
        )
    }

    func testEveryStagedCaptureSelectsTentativeMoverAtItsCommittedSource() throws {
        var captureCaseIDs: Set<String> = []

        for evaluationCase in ModelCoachingEvaluationCorpus.allCases {
            let request = evaluationCase.request
            guard let tentativeID = request.currentInteraction.tentativeMoveReference,
                  let move = request.chessEvidence.legalMoves.first(where: { $0.id == tentativeID }),
                  move.capturePieceReference != nil else {
                continue
            }
            captureCaseIDs.insert(evaluationCase.id)

            let selectedID = try XCTUnwrap(
                request.currentInteraction.selectedPieceReference,
                "\(evaluationCase.id) omitted the staged capture's mover selection"
            )
            let selectedPiece = try XCTUnwrap(
                request.chessEvidence.pieces.first { $0.id == selectedID },
                "\(evaluationCase.id) selected an undeclared piece"
            )
            XCTAssertEqual(selectedID, move.sourcePieceReference, evaluationCase.id)
            XCTAssertEqual(selectedPiece.square, String(move.canonicalMove.prefix(2)), evaluationCase.id)
            XCTAssertEqual(selectedPiece.color, request.currentPosition.sideToMove, evaluationCase.id)
        }

        XCTAssertEqual(captureCaseIDs, ["t6Capture", "t7UnsafeCapture", "t12Capture"])
    }

    func testEveryRequestHasClosedPermittedSetsAndCoherentOracleReferences() {
        for evaluationCase in ModelCoachingEvaluationCorpus.allCases {
            let request = evaluationCase.request
            let permitted = request.permittedReferences
            let evidenceIDs = Set(
                request.chessEvidence.legalMoves.map(\.id)
                    + request.chessEvidence.immediateReplies.map(\.id)
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

    private func sourceReferences(in request: ModelCoachingRequest) -> Set<String> {
        Set(
            request.permittedReferences.actions.map(\.id)
                + request.permittedReferences.boardTasks.map(\.id)
                + request.chessEvidence.pieces.map(\.id)
                + request.chessEvidence.legalMoves.map(\.id)
                + request.chessEvidence.relationships.map(\.id)
                + request.chessEvidence.immediateReplies.map(\.id)
                + request.chessEvidence.tacticalFacts.map(\.id)
        )
    }

    private func aliasTokens(in markdown: String) -> Set<String> {
        let pattern = #"\b(?:action|task|piece|move|relationship|reply|fact)-[a-z0-9-]+\b"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(markdown.startIndex..., in: markdown)
        return Set(expression.matches(in: markdown, range: range).compactMap { match in
            Range(match.range, in: markdown).map { String(markdown[$0]) }
        })
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

    private func authoritativeFENFields(_ fen: String) -> ArraySlice<Substring> {
        fen.split(separator: " ").prefix(4)
    }

    private func replay(
        _ history: [ModelCoachingHistoryMove],
        from initialState: GameState
    ) throws -> (finalState: GameState, repetitionCounts: [String: Int]) {
        var state = initialState
        var repetitionCounts = [repetitionKey(for: state): 1]

        for entry in history {
            let move = try ordinaryMove(from: entry.canonicalMove)
            XCTAssertTrue(
                LegalMoveGenerator.allLegalMoves(in: state).contains(move),
                "Committed history contains illegal move \(entry.canonicalMove)"
            )
            state.apply(move)
            repetitionCounts[repetitionKey(for: state), default: 0] += 1
        }

        return (state, repetitionCounts)
    }

    private func ordinaryMove(from canonicalMove: String) throws -> Move {
        let characters = Array(canonicalMove)
        guard characters.count == 4 else {
            throw CorpusHistoryReplayError.nonOrdinaryMove(canonicalMove)
        }
        return Move(
            from: sq(String(characters[0...1])),
            to: sq(String(characters[2...3]))
        )
    }

    private func repetitionKey(for state: GameState) -> String {
        authoritativeFENFields(ModelCoachingPositionEncoder.fen(for: state))
            .joined(separator: " ")
    }
}

private enum CorpusHistoryReplayError: Error {
    case nonOrdinaryMove(String)
}
