import XCTest
@testable import ChessTutor

final class ModelCoachingCompactContextTests: XCTestCase {
    func testEveryCorpusRequestCompilesDeterministicallyWithCompleteReferenceAccounting() throws {
        for evaluationCase in ModelCoachingEvaluationCorpus.allCases {
            let request = evaluationCase.request
            let first = try ModelCoachingContextCompiler.compile(request, promptVersion: "tutor-v3")
            let second = try ModelCoachingContextCompiler.compile(request, promptVersion: "tutor-v3")
            let boundIDs = first.referenceBindings.map(\.stableID)
            let omittedIDs = first.omissions.map(\.stableID)

            XCTAssertEqual(first, second, evaluationCase.id)
            XCTAssertEqual(first.schemaVersion, "model-coaching-context.v1", evaluationCase.id)
            XCTAssertEqual(first.promptVersion, "tutor-v3", evaluationCase.id)
            XCTAssertEqual(first.requestID, request.requestID, evaluationCase.id)
            XCTAssertEqual(first.positionRevision, request.positionRevision, evaluationCase.id)
            XCTAssertFalse(first.markdown.isEmpty, evaluationCase.id)
            XCTAssertEqual(boundIDs, boundIDs.sorted(), evaluationCase.id)
            XCTAssertEqual(omittedIDs, omittedIDs.sorted(), evaluationCase.id)
            XCTAssertEqual(Set(first.referenceBindings.map(\.alias)).count, first.referenceBindings.count, evaluationCase.id)
            XCTAssertEqual(Set(boundIDs).count, boundIDs.count, evaluationCase.id)
            XCTAssertEqual(Set(omittedIDs).count, omittedIDs.count, evaluationCase.id)
            XCTAssertEqual(
                allSourceReferences(in: request),
                Set(boundIDs).union(omittedIDs),
                evaluationCase.id
            )
            XCTAssertTrue(Set(boundIDs).isDisjoint(with: omittedIDs), evaluationCase.id)
        }
    }

    func testOpeningUsesCompleteAbsenceSummariesAndBoundedMoveIdeas() throws {
        let compilation = try compile("t1Entry")

        XCTAssertTrue(compilation.markdown.contains(
            "Danger scan — complete: no learner piece is in immediate danger."
        ))
        XCTAssertTrue(compilation.markdown.contains(
            "Safe captures — complete: no useful safe capture exists."
        ))
        XCTAssertTrue(compilation.markdown.contains("Knight "))
        XCTAssertTrue(compilation.markdown.contains("Pawn "))
        XCTAssertLessThanOrEqual(
            compilation.referenceBindings.filter { $0.category == .move }.count,
            3
        )
        XCTAssertFalse(compilation.markdown.contains("immediateReplies"))
        XCTAssertFalse(compilation.markdown.contains("legalMoves"))
        XCTAssertFalse(compilation.markdown.contains("{\""))
        assertSectionOrder(in: compilation.markdown, includesStagedMove: false, includesMoveIdeas: true)
    }

    func testDangerContextBindsEndangeredPieceAttackerFactAndBoardTask() throws {
        let evaluationCase = try corpusCase("t3Entry")
        let compilation = try ModelCoachingContextCompiler.compile(
            evaluationCase.request,
            promptVersion: "tutor-v3"
        )
        let dangerFact = try XCTUnwrap(
            evaluationCase.request.chessEvidence.tacticalFacts.first { $0.kind == .dangerLoss }
        )
        let attackerRelationship = try XCTUnwrap(
            evaluationCase.request.chessEvidence.relationships.first {
                $0.kind == .attacks && dangerFact.subjectReferences.contains($0.targetReference)
            }
        )

        XCTAssertTrue(compilation.referenceBindings.contains { $0.stableID == dangerFact.id })
        XCTAssertTrue(compilation.referenceBindings.contains { $0.stableID == attackerRelationship.id })
        XCTAssertTrue(compilation.referenceBindings.contains {
            $0.stableID == attackerRelationship.sourceReference
        })
        XCTAssertTrue(compilation.referenceBindings.contains {
            $0.stableID == attackerRelationship.targetReference
        })
        XCTAssertTrue(compilation.referenceBindings.contains {
            $0.category == .boardTask && $0.label.contains("identifyPiece")
        })
        XCTAssertTrue(compilation.markdown.contains("Danger scan — complete:"))
    }

    func testStagedMoveAfterNoCaptureAnswerIsLatestAndObsoleteStepIsNotAvailable() throws {
        let compilation = try compile("t7NoSafeCapture")

        XCTAssertTrue(compilation.markdown.contains("c4-d3"))
        XCTAssertTrue(compilation.markdown.contains("Latest event: moveStaged"))
        XCTAssertTrue(compilation.markdown.contains("no-safe-capture answer accepted"))
        XCTAssertFalse(compilation.referenceBindings.contains {
            $0.stableID == "action:noSafeCapture"
        })
        assertSectionOrder(in: compilation.markdown, includesStagedMove: true, includesMoveIdeas: false)
    }

    func testRemovedUnsafeBishopMoveKeepsOnlyCriticalExplanatoryReplies() throws {
        let evaluationCase = try corpusCase("t11UnsafeBishopFound")
        let compilation = try ModelCoachingContextCompiler.compile(
            evaluationCase.request,
            promptVersion: "tutor-v3"
        )
        let moveID = "move:f1-a6"
        let allMoveReplies = evaluationCase.request.chessEvidence.immediateReplies.filter {
            $0.afterMoveReference == moveID
        }
        let boundMoveReplies = compilation.referenceBindings.filter {
            $0.category == .reply && allMoveReplies.map(\.id).contains($0.stableID)
        }

        XCTAssertTrue(compilation.markdown.contains("f1-a6"))
        XCTAssertTrue(compilation.markdown.contains("Current status: removed"))
        XCTAssertTrue(compilation.markdown.contains("Unsafe issues:"))
        XCTAssertFalse(boundMoveReplies.isEmpty)
        XCTAssertLessThanOrEqual(boundMoveReplies.count, 2)
        XCTAssertLessThan(boundMoveReplies.count, allMoveReplies.count)
    }

    func testReplacementMoveIsAuthoritativeAndOldOutsidePawnMoveIsLowerPriority() throws {
        let compilation = try compile("t11Safe")

        XCTAssertTrue(compilation.markdown.contains("g1-f3"))
        XCTAssertTrue(compilation.markdown.contains("Latest event: moveReplaced"))
        XCTAssertFalse(compilation.markdown.contains("h2-h4"))
        XCTAssertTrue(compilation.omissions.contains {
            $0.stableID == "move:h2-h4" && $0.reason == .lowerPriorityCandidate
        })
    }

    func testLatestInspectedOpponentPieceKeepsItsReplyToTheStagedDestination() throws {
        let compilation = try compile("t11BenignCaptureTap")
        let replyID = "reply:move:e7-e6->move:c4-e6"

        XCTAssertTrue(compilation.referenceBindings.contains {
            $0.stableID == replyID && $0.category == .reply
        })
        XCTAssertTrue(compilation.markdown.contains("Inspected reply:"))
        XCTAssertTrue(compilation.markdown.contains("reply-c4-e6"))
        XCTAssertLessThanOrEqual(
            compilation.referenceBindings.filter { $0.category == .reply }.count,
            1
        )
    }

    func testReopenedHelpRetainsOrderedTurnHistoryAndRendersPositionOnce() throws {
        let evaluationCase = try corpusCase("t12UnsupportedEntry")
        let compilation = try ModelCoachingContextCompiler.compile(
            evaluationCase.request,
            promptVersion: "tutor-v3"
        )
        let expectedSummaries = evaluationCase.request.currentTurnCoachingHistory.map(\.summary)
        let offsets = try expectedSummaries.map { summary in
            try XCTUnwrap(compilation.markdown.range(of: summary)?.lowerBound, summary)
        }

        XCTAssertEqual(offsets, offsets.sorted(), "history order changed")
        XCTAssertEqual(
            compilation.markdown.components(separatedBy: evaluationCase.request.currentPosition.fen).count - 1,
            1
        )
        XCTAssertTrue(compilation.markdown.contains("Latest event: helpReopened"))
    }

    func testRendererUsesFixedOrderAndEscapesImportedText() {
        let document = ModelCoachingContextDocument(
            metadataLines: [
                "- Schema: `model-coaching-context.v1`",
                "- Prompt: `tutor-v3`",
                "- Request: `request-1`",
                "- Position revision: 1",
            ],
            sections: [
                ModelCoachingMarkdownSection(
                    heading: "Current situation",
                    lines: ["Learner note: use `this`\nwithout\tcontrols"]
                )
            ]
        )

        XCTAssertEqual(
            ModelCoachingMarkdownRenderer.render(document),
            """
            # Chess coaching context

            - Schema: `model-coaching-context.v1`
            - Prompt: `tutor-v3`
            - Request: `request-1`
            - Position revision: 1

            ## Current situation

            Learner note: use \\`this\\` without controls
            """
        )
    }

    private func compile(_ id: String) throws -> ModelCoachingContextCompilation {
        try ModelCoachingContextCompiler.compile(
            corpusCase(id).request,
            promptVersion: "tutor-v3"
        )
    }

    private func corpusCase(_ id: String) throws -> ModelCoachingEvaluationCase {
        try XCTUnwrap(ModelCoachingEvaluationCorpus.allCases.first { $0.id == id })
    }

    private func allSourceReferences(in request: ModelCoachingRequest) -> Set<String> {
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

    private func assertSectionOrder(
        in markdown: String,
        includesStagedMove: Bool,
        includesMoveIdeas: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var headings = [
            "# Current situation",
            "## Latest action",
            "## History",
            "## Complete tactical summary",
        ]
        if includesStagedMove {
            headings.append("## Staged move")
        }
        if includesMoveIdeas {
            headings.append("## Selected move ideas")
        }
        headings.append("## Available response references")

        let offsets = headings.compactMap { markdown.range(of: $0)?.lowerBound }
        XCTAssertEqual(offsets.count, headings.count, "missing section", file: file, line: line)
        XCTAssertEqual(offsets, offsets.sorted(), "section order changed", file: file, line: line)
    }
}
