import Foundation
import XCTest
@testable import ChessTutor

final class ModelCoachingChessNativeContextCompilerTests: XCTestCase {
    func testHostedV11ContractMakesExpectedResponseAuthoritative() throws {
        let request = request(for: ModelCoachingNeutralPromptExamples.fixtures[0])
        let compilation = ModelCoachingChessNativeContextCompiler.compile(
            request,
            promptVersion: "tutor-v11"
        )

        XCTAssertEqual(["hint"], compilation.availableActions)
        XCTAssertTrue(
            compilation.markdown.contains(
                "Expected response: none, findEndangeredPiece, findSafeCapture, "
                    + "stageMove, judgeMoveSafety, chooseWhetherToPlay"
            )
        )

        let legacy = ModelCoachingChessNativeContextCompiler.compile(
            request,
            promptVersion: "tutor-v10"
        )
        XCTAssertEqual(["hint", "noPieceNeedsHelp"], legacy.availableActions)
        XCTAssertTrue(
            legacy.markdown.contains(
                "Expected response: none, selectPiece, stageMove"
            )
        )
    }

    func testHostedV12PreservesAuthoritativeExpectedResponseContract() throws {
        let request = request(for: ModelCoachingNeutralPromptExamples.fixtures[0])
        let compilation = ModelCoachingChessNativeContextCompiler.compile(
            request,
            promptVersion: "tutor-v12"
        )

        XCTAssertEqual(["hint"], compilation.availableActions)
        XCTAssertTrue(
            compilation.markdown.contains(
                "Expected response: none, findEndangeredPiece, findSafeCapture, "
                    + "stageMove, judgeMoveSafety, chooseWhetherToPlay"
            )
        )
    }

    func testHostedV10ContractMatchesServerInteractionActions() throws {
        let request = request(for: ModelCoachingNeutralPromptExamples.fixtures[0])
        let compilation = ModelCoachingChessNativeContextCompiler.compile(
            request,
            promptVersion: "tutor-v10"
        )
        let contract = ModelCoachingChessNativeContextCompiler.responseContract(
            for: request,
            promptVersion: "tutor-v10"
        )

        XCTAssertEqual(["hint", "noPieceNeedsHelp"], compilation.availableActions)
        XCTAssertEqual(compilation.availableActions, contract.availableActions)
        XCTAssertTrue(
            compilation.markdown.contains(
                "Expected response: none, selectPiece, stageMove"
            )
        )
    }

    func testResponseContractMatchesCompilationWithoutRenderingDependency() {
        for fixture in ModelCoachingNeutralPromptExamples.fixtures {
            let request = request(for: fixture)
            let contract = ModelCoachingChessNativeContextCompiler.responseContract(for: request)
            let compilation = ModelCoachingChessNativeContextCompiler.compile(
                request,
                promptVersion: "tutor-v6"
            )

            XCTAssertEqual(contract.availableActions, compilation.availableActions, fixture.id)
            XCTAssertEqual(contract.availableMoveFocus, compilation.availableMoveFocus, fixture.id)
        }
    }

    func testSharedPythonSwiftContextFixtureCompilesExactly() throws {
        let fixtureURL = repositoryRoot.appendingPathComponent(
            "Tools/CoachingEval/fixtures/chess-native-context-v1.json"
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        let requestObject = try XCTUnwrap(root["request"] as? [String: Any])
        let requestData = try JSONSerialization.data(withJSONObject: requestObject)
        let request = try JSONDecoder().decode(ModelCoachingNeutralRequest.self, from: requestData)
        let compilation = ModelCoachingChessNativeContextCompiler.compile(
            request,
            promptVersion: "tutor-v6"
        )
        let expectedMoves = try XCTUnwrap(root["expectedMoveFocus"] as? [[String]])
            .map { ModelCoachingChessNativeMoveFocus(from: $0[0], to: $0[1]) }

        XCTAssertEqual(compilation.markdown, root["expectedMarkdown"] as? String)
        XCTAssertEqual(compilation.availableActions, root["expectedActions"] as? [String])
        XCTAssertEqual(compilation.availableMoveFocus, expectedMoves)
    }

    func testEightProductionFixturesUseFixedSectionsWithoutNumberedAliases() throws {
        for fixture in ModelCoachingNeutralPromptExamples.fixtures {
            let compilation = compile(fixture)

            XCTAssertEqual(
                markdownHeadings(in: compilation.markdown),
                [
                    "# Chess coaching situation",
                    "## Position",
                    "## Latest interaction",
                    "## Relevant legal facts",
                    "## Available UI response",
                ],
                fixture.id
            )
            for pattern in [
                #"relationship-[0-9]+"#,
                #"move-[0-9]+"#,
                #"piece-[0-9]+"#,
                #"action-[0-9]+"#,
            ] {
                XCTAssertFalse(
                    containsRegex(pattern, in: compilation.markdown),
                    "\(fixture.id) contains alias matching \(pattern)"
                )
            }
        }
    }

    func testCompilationPreservesMetadataCompleteHistoryAndSeparateTentativeMove() {
        for fixture in ModelCoachingNeutralPromptExamples.fixtures {
            let request = request(for: fixture)
            let compilation = ModelCoachingChessNativeContextCompiler.compile(
                request,
                promptVersion: "tutor-v6"
            )
            let expectedHistory = request.gameHistory.isEmpty
                ? "none"
                : request.gameHistory.map(\.displayNotation).joined(separator: " ")
            let expectedTentative = request.interaction.tentativeMove?.san ?? "none"

            XCTAssertEqual(compilation.schemaVersion, "model-coaching-chess-native-context.v1", fixture.id)
            XCTAssertEqual(compilation.promptVersion, "tutor-v6", fixture.id)
            XCTAssertEqual(compilation.requestID, request.requestID, fixture.id)
            XCTAssertEqual(compilation.positionRevision, request.positionRevision, fixture.id)
            XCTAssertEqual(lines(startingWith: "FEN: ", in: compilation.markdown), ["FEN: \(request.position.fen)"], fixture.id)
            XCTAssertEqual(lines(startingWith: "Moves: ", in: compilation.markdown), ["Moves: \(expectedHistory)"], fixture.id)
            XCTAssertEqual(
                lines(startingWith: "Tentative move: ", in: section("Position", of: compilation.markdown)),
                ["Tentative move: \(expectedTentative)"],
                fixture.id
            )
        }
    }

    func testNoSelectionDoesNotDumpMovesOrRelationships() throws {
        for index in [0, 1, 7] {
            let fixture = ModelCoachingNeutralPromptExamples.fixtures[index]
            let compilation = compile(fixture)
            let facts = section("Relevant legal facts", of: compilation.markdown)

            XCTAssertFalse(facts.contains("Legal moves for"), fixture.id)
            XCTAssertFalse(facts.contains("Opponent immediate replies"), fixture.id)
            XCTAssertFalse(facts.contains("attacks"), fixture.id)
            XCTAssertFalse(facts.contains("defends"), fixture.id)
            XCTAssertFalse(facts.contains("can capture"), fixture.id)
            XCTAssertFalse(facts.contains("can recapture"), fixture.id)
            XCTAssertEqual(compilation.availableMoveFocus, [], fixture.id)
            XCTAssertTrue(
                section("Available UI response", of: compilation.markdown)
                    .contains("Allowable move focus: none"),
                fixture.id
            )
        }
    }

    func testSelectedPieceListsOnlyThatPiecesLegalMoves() throws {
        let fixture = ModelCoachingNeutralPromptExamples.fixtures[2]
        let compilation = compile(fixture)
        let facts = section("Relevant legal facts", of: compilation.markdown)

        XCTAssertTrue(facts.contains("Selected piece: White knight on f3"))
        XCTAssertTrue(
            facts.contains("Legal moves for White knight on f3: Nd4, Ne5, Ng1, Ng5, Nh4")
        )
        XCTAssertFalse(facts.contains("Legal captures:"))
        XCTAssertFalse(facts.contains("Checking moves:"))
        XCTAssertFalse(facts.contains("Mating moves:"))
        XCTAssertFalse(facts.contains("Attackers on selected piece:"))
        XCTAssertFalse(facts.contains("Defenders of selected piece:"))
        XCTAssertEqual(
            compilation.availableMoveFocus,
            [
                .init(from: "f3", to: "d4"),
                .init(from: "f3", to: "e5"),
                .init(from: "f3", to: "g1"),
                .init(from: "f3", to: "g5"),
                .init(from: "f3", to: "h4"),
            ]
        )
    }

    func testReplacementLatestInteractionIncludesOnlyOldAndCurrentTentativeMoves() throws {
        let fixture = ModelCoachingNeutralPromptExamples.fixtures[3]
        let compilation = compile(fixture)
        let interaction = section("Latest interaction", of: compilation.markdown)

        XCTAssertEqual(nonemptyBodyLines(in: interaction), ["White replaced h4 with Nf3."])
        XCTAssertEqual(occurrences(of: "h4", in: interaction), 1)
        XCTAssertEqual(occurrences(of: "Nf3", in: interaction), 1)
        XCTAssertFalse(interaction.contains("Help opened"))
        XCTAssertFalse(interaction.contains("Move staged"))
    }

    func testTentativeMovesIncludeLegalityAndOnlyImmediateForcingReplies() throws {
        let expectations: [(index: Int, move: String, replies: String)] = [
            (3, "Nf3", "none"),
            (4, "Bb5", "axb5"),
            (6, "Bd2", "Bxd2+"),
        ]

        for expectation in expectations {
            let fixture = ModelCoachingNeutralPromptExamples.fixtures[expectation.index]
            let compilation = compile(fixture)
            let facts = section("Relevant legal facts", of: compilation.markdown)

            XCTAssertTrue(facts.contains("Tentative move \(expectation.move) is legal."), fixture.id)
            XCTAssertTrue(
                facts.contains("Opponent immediate replies that capture, check, or mate: \(expectation.replies)"),
                fixture.id
            )
            XCTAssertFalse(facts.contains("Direct relationships"), fixture.id)
            XCTAssertFalse(facts.contains("after reply"), fixture.id)
            XCTAssertFalse(facts.contains("after tentative"), fixture.id)
        }
    }

    func testInspectedOpponentPieceListsOnlyItsMatchingRepliesOnceWithoutDownstreamRelationships() throws {
        let fixture = ModelCoachingNeutralPromptExamples.fixtures[5]
        let compilation = compile(fixture)
        let interaction = section("Latest interaction", of: compilation.markdown)
        let facts = section("Relevant legal facts", of: compilation.markdown)

        XCTAssertEqual(nonemptyBodyLines(in: interaction), ["The child tapped the black queen on h4."])
        XCTAssertTrue(facts.contains("Inspected piece: Black queen on h4"))
        XCTAssertTrue(facts.contains("Matching immediate replies: Qxe4+, Qxf2+, Qxh2"))
        for notation in ["Qxe4+", "Qxf2+", "Qxh2"] {
            XCTAssertEqual(occurrences(of: notation, in: compilation.markdown), 1, notation)
        }
        XCTAssertFalse(compilation.markdown.contains("Direct relationships"))
        XCTAssertFalse(compilation.markdown.localizedCaseInsensitiveContains("after reply"))
        XCTAssertFalse(compilation.markdown.localizedCaseInsensitiveContains("after tentative"))
        XCTAssertFalse(compilation.markdown.contains("relationship:"))
        XCTAssertEqual(
            compilation.availableMoveFocus,
            [
                .init(from: "b1", to: "c3"),
                .init(from: "h4", to: "e4"),
                .init(from: "h4", to: "f2"),
                .init(from: "h4", to: "h2"),
            ]
        )
    }

    func testFriendlyInspectionAfterTentativeMoveKeepsGeneralImmediateReplies() {
        let original = request(for: ModelCoachingNeutralPromptExamples.fixtures[5])
        let inspectedEvent = ModelCoachingNeutralEpisodeEvent(
            sequence: 3,
            kind: .squareInspected,
            referencedIDs: ["piece:white:bishop:c4"]
        )
        let request = replacingInteraction(
            in: original,
            with: ModelCoachingNeutralInteraction(
                selectedSquare: original.interaction.selectedSquare,
                selectedPieceReference: original.interaction.selectedPieceReference,
                tentativeMove: original.interaction.tentativeMove,
                latestEvent: inspectedEvent,
                episodeEvents: Array(original.interaction.episodeEvents.dropLast()) + [inspectedEvent]
            )
        )

        let compilation = ModelCoachingChessNativeContextCompiler.compile(
            request,
            promptVersion: "tutor-v6"
        )
        let facts = section("Relevant legal facts", of: compilation.markdown)

        XCTAssertTrue(
            facts.contains("Opponent immediate replies that capture, check, or mate: Qxe4+, Qxf2+, Qxh2")
        )
        XCTAssertFalse(facts.contains("Inspected piece:"))
        XCTAssertFalse(facts.contains("Matching immediate replies:"))
    }

    func testUnavailablePriorReplacementMoveUsesReadableSquarePair() {
        let original = request(for: ModelCoachingNeutralPromptExamples.fixtures[3])
        let priorEvent = ModelCoachingNeutralEpisodeEvent(
            sequence: 2,
            kind: .moveStaged,
            referencedIDs: ["move:e2-e5"]
        )
        let interaction = ModelCoachingNeutralInteraction(
            selectedSquare: original.interaction.selectedSquare,
            selectedPieceReference: original.interaction.selectedPieceReference,
            tentativeMove: original.interaction.tentativeMove,
            latestEvent: original.interaction.latestEvent,
            episodeEvents: [original.interaction.episodeEvents[0], priorEvent, original.interaction.latestEvent]
        )
        let request = replacingInteraction(in: original, with: interaction)

        let compilation = ModelCoachingChessNativeContextCompiler.compile(
            request,
            promptVersion: "tutor-v6"
        )

        XCTAssertEqual(
            nonemptyBodyLines(in: section("Latest interaction", of: compilation.markdown)),
            ["White replaced e2-e5 with Nf3."]
        )
    }

    func testLatestInteractionUsesOnlyLatestProductionEvent() throws {
        let expectedLines = [
            "Help opened.",
            "Help opened.",
            "White selected the knight on f3.",
            "White replaced h4 with Nf3.",
            "White tentatively played Bb5.",
            "The child tapped the black queen on h4.",
            "White tentatively played Bd2.",
            "Help opened.",
        ]

        for (fixture, expectedLine) in zip(ModelCoachingNeutralPromptExamples.fixtures, expectedLines) {
            let interaction = section("Latest interaction", of: compile(fixture).markdown)
            XCTAssertEqual(nonemptyBodyLines(in: interaction), [expectedLine], fixture.id)
        }
    }

    func testActionsAndMoveFocusUseSemanticValuesOnce() throws {
        let compilation = compile(ModelCoachingNeutralPromptExamples.fixtures[4])
        let available = section("Available UI response", of: compilation.markdown)

        XCTAssertEqual(compilation.availableActions, ["hint", "playMove", "tryAnotherMove"])
        XCTAssertEqual(
            compilation.availableMoveFocus,
            [
                .init(from: "c4", to: "b5"),
                .init(from: "a6", to: "b5"),
            ]
        )
        XCTAssertTrue(available.contains("Actions: hint, playMove, tryAnotherMove"))
        XCTAssertTrue(available.contains("Square focus: any board square"))
        XCTAssertTrue(available.contains("Allowable move focus: c4-b5, a6-b5"))
        XCTAssertEqual(occurrences(of: "c4-b5", in: compilation.markdown), 1)
        XCTAssertEqual(occurrences(of: "a6-b5", in: compilation.markdown), 1)
    }

    func testCompilationIsByteDeterministic() {
        for fixture in ModelCoachingNeutralPromptExamples.fixtures {
            let request = request(for: fixture)
            XCTAssertEqual(
                ModelCoachingChessNativeContextCompiler.compile(request, promptVersion: "tutor-v6"),
                ModelCoachingChessNativeContextCompiler.compile(request, promptVersion: "tutor-v6"),
                fixture.id
            )
        }
    }

    private func compile(
        _ fixture: ModelCoachingNeutralPromptFixture
    ) -> ModelCoachingChessNativeContextCompilation {
        ModelCoachingChessNativeContextCompiler.compile(
            request(for: fixture),
            promptVersion: "tutor-v6"
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func request(
        for fixture: ModelCoachingNeutralPromptFixture
    ) -> ModelCoachingNeutralRequest {
        ModelCoachingNeutralRequestBuilder.build(
            snapshot: fixture.snapshot,
            requestID: fixture.id
        )
    }

    private func replacingInteraction(
        in request: ModelCoachingNeutralRequest,
        with interaction: ModelCoachingNeutralInteraction
    ) -> ModelCoachingNeutralRequest {
        ModelCoachingNeutralRequest(
            schemaVersion: request.schemaVersion,
            requestID: request.requestID,
            positionRevision: request.positionRevision,
            position: request.position,
            gameHistory: request.gameHistory,
            interaction: interaction,
            pieces: request.pieces,
            legalMoves: request.legalMoves,
            occupiedSquareRelationships: request.occupiedSquareRelationships,
            tentativeReplies: request.tentativeReplies,
            capabilities: request.capabilities
        )
    }

    private func markdownHeadings(in markdown: String) -> [String] {
        markdown.split(separator: "\n").map(String.init).filter { $0.hasPrefix("#") }
    }

    private func section(_ heading: String, of markdown: String) -> String {
        let marker = "## \(heading)"
        guard let start = markdown.range(of: marker) else { return "" }
        let remainder = markdown[start.lowerBound...]
        guard let next = remainder.dropFirst(marker.count).range(of: "\n\n## ") else {
            return String(remainder)
        }
        return String(remainder[..<next.lowerBound])
    }

    private func nonemptyBodyLines(in section: String) -> [String] {
        Array(section.split(separator: "\n").dropFirst()).map(String.init)
    }

    private func lines(startingWith prefix: String, in text: String) -> [String] {
        text.split(separator: "\n").map(String.init).filter { $0.hasPrefix(prefix) }
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func containsRegex(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
