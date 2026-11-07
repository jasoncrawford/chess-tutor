import Foundation
import XCTest
@testable import ChessTutor

/// New grading policy; the original benchmark and its historical scores stay frozen.
enum CoachingExperienceBenchmark {
    static let manifestVersion = "coaching-quality-experience-regression-manifest.v4"
    static func corpus() throws -> CoachingQualityBenchmarkCorpus {
        let sources = CoachingQualityBenchmarkCorpus.v1.developmentTurns
            + (try CoachingPlaythroughBenchmark.corpus().allTurns)
            + (try CoachingLaterGameBenchmark.corpus().allTurns)
        let definitions: [(String, String, [String], String)] = [
            ("e01-knight-defense", "m01-safe-development", [
                "After the staged b1-c3, the knight attacks d5 and defends e2, not d4. A knight on c3 cannot protect a pawn on d4.",
            ], "Explain a concrete, accurate consequence of the staged move. A claimed knight defense of d4 is a factual error, chess correctness at most 2."),
            ("e02-explain-answer", "p07-defended-piece-answer", [],
             "Acknowledge the selected bishop and explain that the pawn can recapture if the queen takes it, before any new coaching step. Jumping straight to a capture question without that explanation is at most 3 for latest-action responsiveness and coaching judgment, even if the new question is useful."),
            ("e03-selected-danger", "i01-selected-attacked-piece", [],
             "Respond meaningfully to the selected endangered piece, acknowledging the child's discovery and offering a relevant next step. Ignoring the selection or asking the same identification question again is at most 3 for latest-action responsiveness."),
            ("e04-opening-discovery", "q01-starting-position", [],
             "Offer a concrete beginner goal and room to choose a move. Ordinary Help must not dictate an exact piece-to-square move or visually supply it; that is at most 3 for discovery. Empty encouragement without a usable goal is at most 3 for coaching judgment. Do not ask an unnecessary danger or capture question."),
            ("e05-requested-hint", "i04-opening-hint", [],
             "The child explicitly requested Hint. Supply a more actionable clue or a concrete move with a simple reason. Precise piece/square guidance and matching focus are allowed and can earn 5 for discovery here; withholding useful help or merely repeating a broad goal is at most 3 for coaching judgment."),
            ("e06-mating-goal", "l06-mating-net-help", [],
             "Help the child aim to trap the lone king, leaving the move to discover. A generic exercise to give any check, without a trapping or escape-square goal, is at most 3 for coaching judgment. Dictating the exact mating move without Hint is at most 3 for discovery. Naming a rook as a clue is acceptable if the trapping goal remains clear."),
            ("e07-concrete-feedback", "p03-bishop-consequence", [],
             "Explain a specific observable consequence of this staged bishop move. Mere development praise or generic center-control language is at most 3 for coaching judgment. Direct explanation with a keep/change response is appropriate and may earn 5 for discovery; another quiz is not required."),
            ("e08-accept-safety-answer", "i07-looks-safe", [
                "The child already chose Looks safe after staging b1-c3. The knight on c3 does not protect d4; it attacks d5 and defends e2.",
            ], "Accept or correct the child's safety answer with a short reason, and move to the keep/change decision. Asking safety again is at most 3 for responsiveness/coherence. Accurate direct confirmation may earn 5 for discovery; do not demand another puzzle."),
            ("e09-stalemate-warning", "l08-staged-stalemate", [],
             "Explain that the staged move causes stalemate, a draw, and allow reconsideration. Omitting the draw while praising confinement or control is at most 2 for coaching judgment, even when each stated geometric fact is true. The child needs the terminal consequence before deciding to play."),
        ]
        let turns = try definitions.map { id, sourceID, facts, purpose in
            let source = try XCTUnwrap(sources.first { $0.id == sourceID })
            var verifiedFacts = source.graderBrief.verifiedFacts + facts
            var severeFailures = ["Invented or reversed chess facts, approving a clearly losing move, stale-stage advice, unavailable UI, or revealing the answer while asking the child to find it."]
            if id == "e06-mating-goal" {
                let request = ModelCoachingNeutralRequestBuilder.build(snapshot: source.snapshot, requestID: "grader-facts")
                let mates = request.legalMoves.filter { $0.isLegal && $0.givesCheckmate }.map(\.canonicalMove).sorted()
                verifiedFacts.append("Complete legal checkmates in one from the committed board: \(mates.isEmpty ? "none" : mates.joined(separator: ", ")). No other legal move gives checkmate in one.")
                severeFailures.append("An impossible piece-specific mating question is false advice and unanswerable, even when phrased as an invitation rather than a statement.")
            }
            return CoachingQualityBenchmarkTurn(
                id: id, groupID: id, stepIndex: 1, split: .development,
                category: source.category, snapshot: source.snapshot,
                graderBrief: .init(
                    verifiedFacts: verifiedFacts,
                    coachingPurpose: purpose,
                    acceptableAlternatives: ["Any natural wording meeting the purpose. Do not require a reference phrase or another discovery question after the child has already acted."],
                    successCriteria: [purpose, "Judge the next interaction as well as the explanation. A clear Play this move / Try another move UI can carry the decision without a formulaic verbal confirmation question."],
                    severeFailureCriteria: severeFailures
                ), sourceTraceID: "experience-v3:\(sourceID)"
            )
        }
        return .init(independent: turns + (try polishTurns()), sequences: [])
    }

    /// Independent staged-move probes, not a scripted prior coach conversation.
    /// Keep the original nine snapshots and briefs above unchanged.
    private static func polishTurns() throws -> [CoachingQualityBenchmarkTurn] {
        let definitions: [(String, [String], String, [String], String)] = [
            ("e10-black-flank-pawn", ["e2e3"], "h7h6", [
                "After the staged h7-h6, Black's pawn on h6 controls g5. No white piece occupies g5.",
                "Black's central pawns remain on d7 and e7. The staged h-pawn move neither occupies the center nor clears a path for Black's bishop on f8, which still has no available move.",
            ], "Explain the actual tradeoff: h6 guards g5, but this quiet opening move leaves central space and bishop development unchanged. Merely reciting g5 control or praising safety without the central/development tradeoff is at most 3 for coaching judgment. Leave room for the child to keep or reconsider the move, without prescribing an exact alternative."),
            ("e11-white-flank-pawn", [], "a2a3", [
                "After the staged a2-a3, White's pawn on a3 controls b4. No black piece occupies b4.",
                "White's central pawns remain on d2 and e2. The staged a-pawn move neither occupies the center nor clears a path for White's bishop on f1, which still has no available move.",
            ], "Transfer the opening tradeoff to White and the other flank: a3 guards b4, but leaves central space and bishop development unchanged. Peripheral-square trivia alone or indiscriminate praise is at most 3 for coaching judgment. Keep the child's choice open; do not prescribe an exact alternative move."),
            ("e12-purposeful-flank-pawn", ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "d7d6", "d2d3", "c8g4"], "h2h3", [
                "After the staged h2-h3, White's pawn on h3 attacks Black's bishop on g4.",
                "This flank-pawn move has an immediate purpose. Black is not forced to retreat the bishop: g4xf3, capturing White's knight, is also legal.",
            ], "Acknowledge the concrete attack on the bishop on g4. Do not apply a blanket rule that flank pawns are bad or repeat an irrelevant center-pawn reprimand. Missing the bishop attack while criticizing the flank move is at most 3 for responsiveness and coaching judgment. Explain calmly without claiming a forced retreat or prescribing the child's next move."),
            ("e13-calm-center-pawn", [], "e2e4", [
                "After the staged e2-e4, White's pawn occupies e4 and controls d5 and f5.",
                "The move clears e2, opening paths for White's bishop on f1 and queen on d1. The bishop can move to c4 and the queen can move to h5, though neither move has been selected or played.",
            ], "Explain a useful result of the staged central pawn move in ordinary, calm language: central space, accurate pawn control, or a newly opened piece path. Generic celebration without a specific consequence is at most 3 for coaching judgment. The child still chooses whether to play it; do not turn the explanation into an exact next-move instruction."),
        ]
        return try definitions.map { id, history, canonical, facts, purpose in
            var state = GameState.startingPosition()
            for recorded in history { state.apply(try CoachingLaterGameBenchmark.legalMove(recorded, in: state)) }
            let move = try CoachingLaterGameBenchmark.legalMove(canonical, in: state)
            let opened = ModelCoachingNeutralEpisodeEvent(sequence: 1, kind: .helpOpened, referencedIDs: [])
            let staged = ModelCoachingNeutralEpisodeEvent(sequence: 2, kind: .moveStaged,
                                                          referencedIDs: [ModelCoachingPositionEncoder.moveID(move)])
            return CoachingQualityBenchmarkTurn(
                id: id, groupID: id, stepIndex: 1, split: .development, category: .tentativeMove,
                snapshot: .init(committedState: state, learner: state.sideToMove, positionRevision: history.count,
                                selectedSquare: move.to, tentativeMove: move, latestEvent: staged, episodeEvents: [opened, staged]),
                graderBrief: .init(
                    verifiedFacts: facts, coachingPurpose: purpose,
                    acceptableAlternatives: ["Any natural, concise wording satisfying the purpose; no reference phrase or extra quiz is required."],
                    successCriteria: [
                        purpose,
                        "Use natural, calm, specific language. Ordinary move feedback should have no exclamation marks or generic Great job-style cheerleading; conspicuous celebration is at most 3 for age-appropriate clarity.",
                        "Preserve learner agency: explain the staged move and let the existing Play this move / Try another move controls carry the choice. Do not prescribe an exact alternative move or visually supply one without a requested Hint.",
                    ],
                    severeFailureCriteria: ["Invented or reversed chess facts, advice about a different staged move, a false forced reply, or requiring unavailable UI."]
                ), sourceTraceID: nil
            )
        }
    }
}

final class CoachingExperienceBenchmarkTests: XCTestCase {
    func testPolishRegressionInventoryExportsThirteenIndependentDevelopmentCases() throws {
        let corpus = try CoachingExperienceBenchmark.corpus()
        let artifacts = try CoachingQualityBenchmarkExporter.artifacts(
            sourceGitSHA: "test", corpus: corpus, regression: true, preserveVerifiedFacts: true,
            regressionSchemaVersion: CoachingExperienceBenchmark.manifestVersion
        )
        let manifest = try JSONDecoder().decode(CoachingQualityBenchmarkManifest.self, from: artifacts.manifestJSON)
        XCTAssertEqual("coaching-quality-experience-regression-manifest.v4", manifest.schemaVersion)
        XCTAssertEqual(13, manifest.turnCount)
        XCTAssertEqual(13, manifest.independentGroupCount)
        XCTAssertEqual(13, manifest.developmentTurnCount)
        XCTAssertEqual(0, manifest.holdoutTurnCount)
        XCTAssertEqual(0, manifest.sequenceGroupCount)
        XCTAssertEqual([
            "e10-black-flank-pawn", "e11-white-flank-pawn", "e12-purposeful-flank-pawn", "e13-calm-center-pawn",
        ], Array(manifest.turnIDs.suffix(4)))
    }

    func testPolishCasesReplayFullLegalHistoryAndKeepStagingSeparate() throws {
        let turns = try CoachingExperienceBenchmark.corpus().allTurns
        let expected: [(String, [String], String, String, String)] = [
            ("e10-black-flank-pawn", ["e2e3"], "black", "h7h6", "rnbqkbnr/pppppppp/8/8/8/4P3/PPPP1PPP/RNBQKBNR b KQkq - 0 1"),
            ("e11-white-flank-pawn", [], "white", "a2a3", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"),
            ("e12-purposeful-flank-pawn", ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "d7d6", "d2d3", "c8g4"], "white", "h2h3", "r2qkbnr/ppp2ppp/2np4/4p3/2B1P1b1/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5"),
            ("e13-calm-center-pawn", [], "white", "e2e4", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"),
        ]
        for (id, history, learner, canonical, fen) in expected {
            let turn = try XCTUnwrap(turns.first { $0.id == id }, id)
            let request = ModelCoachingNeutralRequestBuilder.build(snapshot: turn.snapshot, requestID: id)
            XCTAssertEqual(history, request.gameHistory.map(\.canonicalMove), id)
            XCTAssertEqual(fen, request.position.fen, id)
            XCTAssertEqual(learner, request.position.sideToMove, id)
            XCTAssertEqual(canonical, request.interaction.tentativeMove?.canonicalMove, id)
            XCTAssertEqual(true, request.interaction.tentativeMove?.isLegal, id)
            XCTAssertEqual(.moveStaged, request.interaction.latestEvent.kind, id)
            var replay = GameState.startingPosition()
            for move in history {
                replay.apply(try CoachingLaterGameBenchmark.legalMove(move, in: replay))
            }
            XCTAssertEqual(replay, turn.snapshot.committedState, id)
            let staged = try XCTUnwrap(turn.snapshot.tentativeMove)
            XCTAssertTrue(LegalMoveGenerator.allLegalMoves(in: replay).contains(staged), id)
            XCTAssertEqual(history.count, replay.moveHistory.count, id)
        }
    }

    func testPolishPawnConsequencesMatchRulesRatherThanAnEdgePawnHeuristic() throws {
        let turns = try CoachingExperienceBenchmark.corpus().allTurns
        let square = CoachingPlaythroughBenchmark.square
        for (id, controls, bishop) in [
            ("e10-black-flank-pawn", ["g5"], "f8"),
            ("e11-white-flank-pawn", ["b4"], "f1"),
            ("e12-purposeful-flank-pawn", ["g4"], "f1"),
            ("e13-calm-center-pawn", ["d5", "f5"], "f1"),
        ] {
            let turn = try XCTUnwrap(turns.first { $0.id == id }, id)
            let move = try XCTUnwrap(turn.snapshot.tentativeMove)
            let after = turn.snapshot.committedState.applyingUnchecked(move)
            XCTAssertEqual(Set(controls.map(square)), Set(LegalMoveGenerator.controlledSquares(from: move.to, in: after)), id)
            if ["e10-black-flank-pawn", "e11-white-flank-pawn"].contains(id) {
                XCTAssertEqual(0, LegalMoveGenerator.allowedMoves(for: square(bishop), by: turn.snapshot.learner, in: after).count, id)
            }
            let request = ModelCoachingNeutralRequestBuilder.build(snapshot: turn.snapshot, requestID: id)
            if id == "e12-purposeful-flank-pawn" {
                XCTAssertTrue(try XCTUnwrap(request.tentativePosition).occupiedSquareRelationships.contains {
                    $0.kind == .attacks && $0.sourcePieceReference == "piece:white:pawn:h3" && $0.targetPieceReference == "piece:black:bishop:g4"
                })
                XCTAssertTrue(request.tentativeReplies.contains { $0.canonicalMove == "g4f3" })
            }
            if id == "e13-calm-center-pawn" {
                XCTAssertTrue(LegalMoveGenerator.allowedMoves(for: square("f1"), by: .white, in: after).contains { $0.to == square("c4") })
                XCTAssertTrue(LegalMoveGenerator.allowedMoves(for: square("d1"), by: .white, in: after).contains { $0.to == square("h5") })
            }
        }
    }

    func testPolishGraderCriteriaAreExportedPrivatelyNotAsCandidateContext() throws {
        let corpus = try CoachingExperienceBenchmark.corpus()
        let artifacts = try CoachingQualityBenchmarkExporter.artifacts(
            sourceGitSHA: "test", corpus: corpus, regression: true, preserveVerifiedFacts: true,
            regressionSchemaVersion: CoachingExperienceBenchmark.manifestVersion
        )
        let rows = try artifacts.casesJSONL.split(separator: 0x0A).map {
            try JSONDecoder().decode(CoachingQualityBenchmarkCaseRecord.self, from: Data($0))
        }
        let polishTurns = Array(corpus.allTurns.suffix(4))
        XCTAssertEqual("e10-black-flank-pawn", polishTurns.first?.id)
        for turn in polishTurns {
            let row = try XCTUnwrap(rows.first { $0.id == turn.id })
            XCTAssertEqual(turn.graderBrief.successCriteria, row.graderBrief.successCriteria)
            XCTAssertEqual(turn.graderBrief.severeFailureCriteria, row.graderBrief.severeFailureCriteria)
            let requestJSON = String(decoding: try JSONEncoder().encode(row.request), as: UTF8.self)
            let markdown = ModelCoachingChessNativeContextCompiler.compile(row.request, promptVersion: "tutor-v13").markdown
            let privateText = turn.graderBrief.verifiedFacts + [turn.graderBrief.coachingPurpose]
                + turn.graderBrief.acceptableAlternatives + turn.graderBrief.successCriteria + turn.graderBrief.severeFailureCriteria
            for text in privateText {
                XCTAssertFalse(requestJSON.contains(text), turn.id)
                XCTAssertFalse(markdown.contains(text), turn.id)
            }
        }
    }

    func testStalemateWarningIsARepeatableExperienceRegression() throws {
        let turn = try XCTUnwrap(CoachingExperienceBenchmark.corpus().allTurns.first { $0.id == "e09-stalemate-warning" })
        var after = turn.snapshot.committedState
        after.apply(try XCTUnwrap(turn.snapshot.tentativeMove))
        XCTAssertEqual(.stalemate, after.result)
        XCTAssertFalse(LegalMoveGenerator.isKingInCheck(after.sideToMove, in: after.board))
        XCTAssertTrue(turn.graderBrief.coachingPurpose.contains("Omitting"))
        XCTAssertTrue(turn.graderBrief.verifiedFacts.contains { $0.contains("stalemate, a draw") })
    }

    func testMatingGoalBriefNamesTheCompleteLegalAnswerSet() throws {
        let turn = try XCTUnwrap(CoachingExperienceBenchmark.corpus().allTurns.first { $0.id == "e06-mating-goal" })
        let request = ModelCoachingNeutralRequestBuilder.build(snapshot: turn.snapshot, requestID: "mate-facts")
        let mates = request.legalMoves.filter { $0.isLegal && $0.givesCheckmate }
        XCTAssertEqual(mates.map(\.canonicalMove), ["h3d3"])
        XCTAssertTrue(turn.graderBrief.verifiedFacts.contains("Complete legal checkmates in one from the committed board: h3d3. No other legal move gives checkmate in one."))
        XCTAssertTrue(turn.graderBrief.severeFailureCriteria.contains { $0.contains("impossible") })
    }

    func testTentativeFactsComeFromTheDisplayedBoardIncludingSpecialMoves() throws {
        let turns = CoachingQualityBenchmarkCorpus.v1.developmentTurns
            + (try CoachingExperienceBenchmark.corpus().allTurns)
        var specialCases: Set<String> = []
        for turn in turns {
            let request = ModelCoachingNeutralRequestBuilder.build(snapshot: turn.snapshot, requestID: "facts")
            guard let move = turn.snapshot.tentativeMove else {
                XCTAssertNil(request.tentativePosition)
                continue
            }
            let after = turn.snapshot.committedState.applyingUnchecked(move)
            let facts = try XCTUnwrap(request.tentativePosition, turn.id)
            let expectedIDs = after.board.pieces.map { ModelCoachingPositionEncoder.pieceID($0.value, at: $0.key) }.sorted()
            XCTAssertEqual(facts.pieces.map(\.id), expectedIDs, turn.id)
            XCTAssertEqual(facts.movedPieceControlledSquares, LegalMoveGenerator.controlledSquares(from: move.to, in: after).map(ModelCoachingPositionEncoder.squareName).sorted(), turn.id)
            if ["c06-en-passant", "m06-promotion", "m07-castling"].contains(turn.id) { specialCases.insert(turn.id) }
            if turn.id == "e01-knight-defense" {
                XCTAssertFalse(facts.movedPieceControlledSquares.contains("d4"))
                XCTAssertTrue(facts.occupiedSquareRelationships.contains { $0.sourcePieceReference == "piece:white:knight:c3" && $0.targetPieceReference == "piece:black:pawn:d5" && $0.kind == .attacks })
                XCTAssertFalse(facts.occupiedSquareRelationships.contains { $0.sourcePieceReference == "piece:white:knight:c3" && $0.targetPieceReference == "piece:white:pawn:d4" })
            }
        }
        XCTAssertEqual(specialCases, ["c06-en-passant", "m06-promotion", "m07-castling"])
    }

    func testRequestsUseUnchangedSourceSnapshotsAndPrivateBriefs() throws {
        let corpus = try CoachingExperienceBenchmark.corpus()
        let sources = CoachingQualityBenchmarkCorpus.v1.developmentTurns
            + (try CoachingPlaythroughBenchmark.corpus().allTurns)
            + (try CoachingLaterGameBenchmark.corpus().allTurns)
        XCTAssertEqual(13, corpus.allTurns.count)
        for turn in corpus.allTurns.prefix(9) {
            let sourceID = try XCTUnwrap(turn.sourceTraceID?.split(separator: ":").last).description
            let source = try XCTUnwrap(sources.first { $0.id == sourceID })
            XCTAssertEqual(source.snapshot, turn.snapshot)
            XCTAssertEqual(.development, source.split)
            let request = ModelCoachingNeutralRequestBuilder.build(snapshot: turn.snapshot, requestID: "test")
            let markdown = ModelCoachingChessNativeContextCompiler.compile(request, promptVersion: "tutor-v13").markdown
            XCTAssertFalse(markdown.contains(turn.graderBrief.coachingPurpose))
            XCTAssertFalse(markdown.contains("at most 3"))
        }
        let first = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true, preserveVerifiedFacts: true, regressionSchemaVersion: CoachingExperienceBenchmark.manifestVersion)
        XCTAssertEqual(first, try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true, preserveVerifiedFacts: true, regressionSchemaVersion: CoachingExperienceBenchmark.manifestVersion))
    }

    func testKnightDefenseFactsMatchMovementRules() throws {
        let corpus = try CoachingExperienceBenchmark.corpus()
        let square = CoachingPlaythroughBenchmark.square
        for turn in corpus.allTurns where ["e01-knight-defense", "e08-accept-safety-answer"].contains(turn.id) {
            var state = turn.snapshot.committedState
            state.apply(try XCTUnwrap(turn.snapshot.tentativeMove))
            let controls = LegalMoveGenerator.controlledSquares(from: square("c3"), in: state)
            XCTAssertFalse(controls.contains(square("d4")))
            XCTAssertTrue(controls.contains(square("d5")))
            XCTAssertTrue(controls.contains(square("e2")))
        }
        // Bishop-defense and mating-net positions retain the exact independently
        // verified snapshots covered by the playthrough and later-game tests.
    }

    func testExportRetainsVerifiedCaseFactsOnlyInThePrivateBrief() throws {
        let corpus = try CoachingExperienceBenchmark.corpus()
        let artifacts = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true, preserveVerifiedFacts: true, regressionSchemaVersion: CoachingExperienceBenchmark.manifestVersion)
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: artifacts.manifestJSON) as? [String: Any])
        XCTAssertEqual("coaching-quality-experience-regression-manifest.v4", manifest["schemaVersion"] as? String)
        let rows = try artifacts.casesJSONL.split(separator: 0x0A).map {
            try JSONDecoder().decode(CoachingQualityBenchmarkCaseRecord.self, from: Data($0))
        }
        for (turn, row) in zip(corpus.allTurns, rows) {
            for fact in turn.graderBrief.verifiedFacts {
                XCTAssertTrue(row.graderBrief.verifiedFacts.contains(fact), "Lost fact: \(fact)")
            }
            let markdown = ModelCoachingChessNativeContextCompiler.compile(row.request, promptVersion: "tutor-v13").markdown
            XCTAssertFalse(markdown.contains(turn.graderBrief.coachingPurpose))
        }
    }

    func testOptInExport() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["COACHING_EXPERIENCE_BENCHMARK_OUTPUT_DIR"], !path.isEmpty else { return }
        let source = try XCTUnwrap(env["COACHING_QUALITY_BENCHMARK_SOURCE_SHA"])
        try CoachingQualityBenchmarkExporter.write(to: URL(fileURLWithPath: path), sourceGitSHA: source,
                                                  corpus: CoachingExperienceBenchmark.corpus(), regression: true, preserveVerifiedFacts: true,
                                                  regressionSchemaVersion: CoachingExperienceBenchmark.manifestVersion)
    }
}
