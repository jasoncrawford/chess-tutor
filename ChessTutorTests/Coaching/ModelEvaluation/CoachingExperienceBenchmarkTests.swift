import Foundation
import XCTest
@testable import ChessTutor

/// New grading policy; the original benchmark and its historical scores stay frozen.
enum CoachingExperienceBenchmark {
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
                ), sourceTraceID: "experience-v2:\(sourceID)"
            )
        }
        return .init(independent: turns, sequences: [])
    }
}

final class CoachingExperienceBenchmarkTests: XCTestCase {
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
        XCTAssertEqual(8, corpus.allTurns.count)
        for turn in corpus.allTurns {
            let sourceID = try XCTUnwrap(turn.sourceTraceID?.split(separator: ":").last).description
            let source = try XCTUnwrap(sources.first { $0.id == sourceID })
            XCTAssertEqual(source.snapshot, turn.snapshot)
            XCTAssertEqual(.development, source.split)
            let request = ModelCoachingNeutralRequestBuilder.build(snapshot: turn.snapshot, requestID: "test")
            let markdown = ModelCoachingChessNativeContextCompiler.compile(request, promptVersion: "tutor-v13").markdown
            XCTAssertFalse(markdown.contains(turn.graderBrief.coachingPurpose))
            XCTAssertFalse(markdown.contains("at most 3"))
        }
        let first = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true, preserveVerifiedFacts: true)
        XCTAssertEqual(first, try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true, preserveVerifiedFacts: true))
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
        let artifacts = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true, preserveVerifiedFacts: true)
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
                                                  corpus: CoachingExperienceBenchmark.corpus(), regression: true, preserveVerifiedFacts: true)
    }
}
