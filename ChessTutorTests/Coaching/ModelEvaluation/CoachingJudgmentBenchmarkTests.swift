import Foundation
import XCTest
@testable import ChessTutor

/// Frozen before candidate changes. These are development probes, not holdout evidence.
enum CoachingJudgmentBenchmark {
    static let manifestVersion = "coaching-quality-judgment-regression-manifest.v2"
    static let policy = "Assess decision usefulness, not just factual description. For a staged move, convey whether it is worthwhile and one relevant reason or tradeoff. A true inventory of attacked/defended squares without a decision-useful assessment is at most 3 for coachingJudgment. A clear, proportionate assessment with a relevant reason earns 4–5. An implicit assessment is fine; no required adjective, comparison, exact move, or extra sentence. For Help/Hint, identify a useful goal or opportunity, not merely the first threat. Do not reward verbosity, gratuitous aggression, or matching an engine's favorite. A necessary retreat or sound non-best move can earn 5. Keep factual errors separate from weak judgment."

    static func corpus(version: Int = 2) throws -> CoachingQualityBenchmarkCorpus {
        let activeKnightHistory = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "f3g5", "h7h6"]
        let centerHistory = ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "d2d3", "d7d6", "e1g1", "g8f6"]
        var turns = [
            try make("j01-unnecessary-retreat", state: CoachingPlaythroughBenchmark.state(after: 8), move: "f3g1", facts: [
                "White's developed knight on f3 is not attacked. Returning it to g1 abandons its control of d4/e5 and reoccupies a square needed for castling.",
                "This is legal and does not immediately lose the knight, but uses a turn undoing development. White still has a knight and bishop on their starting squares.",
            ], purpose: "Evaluate the development cost of this safe retreat. Merely describing the knight's new protection of e2/h3 or saying it is safe is at most 3; enthusiastic approval without noticing the lost activity is at most 2. Do not claim a forced loss or that all backward moves are bad."),
            try make("j02-purposeful-retreat", state: CoachingPlaythroughBenchmark.state(after: 14), move: "g5e3", facts: [
                "Black's h6-pawn attacks White's bishop on g5. Moving to e3 escapes that pawn attack and keeps the bishop off its starting square.",
                "The bishop on e3 has open diagonals toward d4/c5 and f4/g5/h6. No black legal reply immediately captures that bishop. Capturing Black's knight on f6 is another legal option; retreat is not the only possible response.",
            ], purpose: "Recognize this as a sensible retreat that saves the bishop while preserving useful activity. Do not penalize it just for going backward or demand a single supposedly best move. A safety explanation tied to the attacked bishop can suffice; a longer strategic lecture is unnecessary."),
            try make("j03-prepare-center", state: replay(centerHistory), move: "c2c3", facts: [
                "White and Black have developed several pieces. White has castled. White's d-pawn is on d3, and the black pawn on e5 contests d4.",
                "The staged c3-pawn controls d4 and b4. It prepares support for a later d3-d4 central advance; it does not immediately attack a black piece or give check.",
                "White's knight on b1 can no longer develop to c3 while the pawn occupies it. This is a tradeoff, not proof c3 is a blunder.",
            ], purpose: "Explain a useful forward plan: supporting a central pawn advance and contesting the center, with proportionate approval of this purposeful quiet move. Merely listing b4/d4 control is at most 3. Do not insist on naming both benefit and cost; one useful reason is enough."),
            try make("j04-rook-activity", state: CoachingPlaythroughBenchmark.state(after: 26), move: "f1e1", facts: [
                "White's e-pawn has captured onto f5. The e2/e3/e4 squares are empty; Black still has a pawn on e5 and queen on e7.",
                "The staged rook on e1 faces Black's e5-pawn down a half-open file. Black's pawn blocks the line to its queen, so this is not an immediate queen attack or a forced win.",
            ], purpose: "Evaluate the rook's more active placement and pressure down the half-open file, giving the child a useful middlegame aim. A mere inventory of squares or safety is at most 3. Do not invent a forced win or say the rook already attacks the queen."),
            try make("j05-active-escape", state: replay(activeKnightHistory), move: "g5f7", facts: [
                "Before the draft Black's h6-pawn attacks White's knight on g5. The knight can capture the pawn on f7, escaping the h-pawn attack.",
                "On f7 the knight attacks Black's queen on d8 and rook on h8. White's bishop on c4 protects f7, so Black's king on e8 cannot legally capture the knight there.",
                "The fork is a concrete attacking opportunity, not just a safe square. This brief does not establish a forced checkmate or an exact longer-term evaluation.",
            ], purpose: "Recognize the active escape and double attack as the move's important benefit. Generic safety or saying only that a pawn was captured is at most 3. Do not miss the fork to recommend retreating instead."),
            try make("j06-counterplay-hint", state: replay(activeKnightHistory), move: nil, hint: true, facts: [
                "Black's h6-pawn attacks White's knight on g5. The legal move g5-f7 captures a pawn and forks Black's queen on d8 and rook on h8.",
                "White's bishop on c4 protects f7, preventing the black king from capturing the knight there. Ordinary knight retreats exist, but overlook this concrete attacking opportunity.",
            ], purpose: "The learner explicitly requested Hint. Help them see an escape with a double attack, not only a backward safe square. Exact move guidance and a matching arrow are allowed. A retreat-only hint that ignores the available fork is at most 3; accurate tactical guidance with a simple reason can earn 5."),
            try make("j07-capture-not-flee", state: CoachingPlaythroughBenchmark.state(after: 32), move: nil, hint: true, facts: [
                "Black's queen on e6 attacks White's queen on g4 and bishop on c4. White can capture that black queen with the bishop from c4.",
                "Black can recapture the bishop with f7xe6, but winning a queen for a bishop is favorable. White can also capture the queen with Qg4xe6; other sound concrete choices need not be penalized solely for differing from a reference move.",
            ], purpose: "Give a useful tactical hint that addresses the danger by taking the attacking queen. Merely retreating an attacked piece or warning that the bishop can be recaptured misses the favorable exchange and is at most 3. No exact preferred capture is required."),
        ]
        let sources = try CoachingPlaythroughBenchmark.corpus().allTurns + CoachingLaterGameBenchmark.corpus().allTurns
        let reused = [
            ("j08-sound-development", "p03-bishop-consequence", "Give proportionate approval of developing this bishop, tied to central influence, active placement, or preparation to castle. Describing an attack on a defended pawn without explaining why the move is useful is at most 3. No exact best-move comparison is required; sensible development should not be condemned for failing to win material."),
            ("j09-favorable-exchange", "p06-queen-for-bishop", "Clearly evaluate the favorable queen-for-bishop trade, despite the recapture. Listing the two captures without conveying that the exchange is worthwhile is at most 3. Do not confuse can be recaptured with a bad move."),
            ("j10-costly-capture", "l01-losing-queen-capture", "Clearly discourage losing a queen for a knight. Listing the attack and recapture without making the material cost understandable is at most 3. The existing overall advantage does not make this exchange sound."),
            ("j11-active-endgame-king", "l03-active-endgame-king", "Connect the safe king advance to a useful endgame job: helping trap the opposing king or supporting White's pieces. An unexplained list of controlled squares is at most 3. Do not apply an opening rule that the king must always hide."),
            ("j12-promotion-plan", "l04-passed-pawn-help", "Point the child toward advancing the passed pawn to promotion, an achievable winning plan. Generic development, checking for harmless threats, or moving a rook without a purpose is at most 3. Ordinary Help should leave a move to discover, rather than dictate the full sequence."),
        ]
        for (id, sourceID, purpose) in reused {
            let source = try XCTUnwrap(sources.first { $0.id == sourceID })
            turns.append(.init(id: id, groupID: id, stepIndex: 1, split: .development,
                               category: source.category, snapshot: source.snapshot,
                               graderBrief: brief(source.graderBrief.verifiedFacts, purpose), sourceTraceID: "judgment-v1:\(sourceID)"))
        }
        if version == 2 {
            turns = turns.map { turn in
                let old = turn.graderBrief
                let clarification = "The displayed board already shows the tentative capture or relocation. Past-tense descriptions such as 'your bishop captured the queen' are acceptable when the response still uses chooseWhetherToPlay and preserves the child's decision. Treating a draft as committed means an actual wrong turn/state assumption (for example, telling the child to wait for Black's turn), not past tense alone."
                return .init(id: turn.id, groupID: turn.groupID, stepIndex: turn.stepIndex, split: turn.split,
                             category: turn.category, snapshot: turn.snapshot,
                             graderBrief: .init(verifiedFacts: old.verifiedFacts, coachingPurpose: old.coachingPurpose,
                                                acceptableAlternatives: old.acceptableAlternatives + [clarification],
                                                successCriteria: old.successCriteria, severeFailureCriteria: old.severeFailureCriteria),
                             sourceTraceID: turn.sourceTraceID)
            }
        }
        return .init(independent: turns, sequences: [])
    }

    private static func replay(_ history: [String]) throws -> GameState {
        var state = GameState.startingPosition()
        for move in history { state.apply(try CoachingLaterGameBenchmark.legalMove(move, in: state)) }
        return state
    }

    private static func make(_ id: String, state: GameState, move canonical: String?, hint: Bool = false,
                             facts: [String], purpose: String) throws -> CoachingQualityBenchmarkTurn {
        let move = try canonical.map { try CoachingLaterGameBenchmark.legalMove($0, in: state) }
        var events = [ModelCoachingNeutralEpisodeEvent(sequence: 1, kind: .helpOpened, referencedIDs: [])]
        if let move { events.append(.init(sequence: 2, kind: .moveStaged, referencedIDs: [ModelCoachingPositionEncoder.moveID(move)])) }
        if hint { events.append(.init(sequence: events.count + 1, kind: .actionChosen, referencedIDs: ["action:hint"])) }
        return .init(id: id, groupID: id, stepIndex: 1, split: .development,
                     category: move == nil ? .interaction : .tentativeMove,
                     snapshot: .init(committedState: state, learner: state.sideToMove,
                                     positionRevision: state.moveHistory.count, selectedSquare: move?.to,
                                     tentativeMove: move, latestEvent: events.last!, episodeEvents: events),
                     graderBrief: brief(facts, purpose), sourceTraceID: nil)
    }

    private static func brief(_ facts: [String], _ purpose: String) -> CoachingQualityBenchmarkGraderBrief {
        .init(verifiedFacts: facts, coachingPurpose: purpose,
              acceptableAlternatives: ["Any short, accurate, age-appropriate response satisfying the purpose; sound alternative plans and natural implicit assessments are accepted."],
              successCriteria: [policy, purpose, "Preserve learner agency and the actual next interaction; do not require an additional quiz after a staged move."],
              severeFailureCriteria: ["False chess claims, approving a clearly losing exchange, claiming a forced win without evidence, treating the draft as committed, or requiring unavailable UI. Weak or incomplete evaluation alone is not a severe error."])
    }
}

final class CoachingJudgmentBenchmarkTests: XCTestCase {
    func testGradingClarificationDoesNotChangeAnyCandidateRequest() throws {
        let original = try CoachingJudgmentBenchmark.corpus(version: 1)
        let revised = try CoachingJudgmentBenchmark.corpus()
        XCTAssertEqual(original.allTurns.map(\.snapshot), revised.allTurns.map(\.snapshot))
        XCTAssertEqual(original.allTurns.map(\.id), revised.allTurns.map(\.id))
        XCTAssertNotEqual(original.allTurns[0].graderBrief, revised.allTurns[0].graderBrief)
    }

    func testExportIsDeterministicAndPrivateCriteriaDoNotLeak() throws {
        let corpus = try CoachingJudgmentBenchmark.corpus()
        let artifacts = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true,
                    preserveVerifiedFacts: true, regressionSchemaVersion: CoachingJudgmentBenchmark.manifestVersion)
        XCTAssertEqual(artifacts, try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true,
                    preserveVerifiedFacts: true, regressionSchemaVersion: CoachingJudgmentBenchmark.manifestVersion))
        let rows = try artifacts.casesJSONL.split(separator: 0x0A).map {
            try JSONDecoder().decode(CoachingQualityBenchmarkCaseRecord.self, from: Data($0))
        }
        XCTAssertEqual(12, rows.count)
        for (turn, row) in zip(corpus.allTurns, rows) {
            XCTAssertEqual(turn.snapshot.committedState.moveHistory.count, row.request.gameHistory.count)
            let requestText = String(decoding: try JSONEncoder().encode(row.request), as: UTF8.self)
            XCTAssertFalse(requestText.contains(CoachingJudgmentBenchmark.policy))
            XCTAssertFalse(requestText.contains(turn.graderBrief.coachingPurpose))
            XCTAssertTrue(row.graderBrief.successCriteria.contains(CoachingJudgmentBenchmark.policy))
        }
    }

    func testRetreatsCenterPlanAndRookPressureMatchTheBoard() throws {
        let turns = try CoachingJudgmentBenchmark.corpus().allTurns
        let square = CoachingPlaythroughBenchmark.square
        var retreat = turns[0].snapshot.committedState
        retreat.apply(try XCTUnwrap(turns[0].snapshot.tentativeMove))
        XCTAssertEqual(Piece(kind: .knight, color: .white), retreat.board[square("g1")])
        let response = ModelCoachingNeutralRequestBuilder.build(snapshot: turns[1].snapshot, requestID: "test")
        XCTAssertFalse(response.tentativeReplies.contains { $0.destinationSquare == "e3" })
        var center = turns[2].snapshot.committedState
        center.apply(try XCTUnwrap(turns[2].snapshot.tentativeMove))
        XCTAssertEqual(Set([square("b4"), square("d4")]), Set(LegalMoveGenerator.controlledSquares(from: square("c3"), in: center)))
        var rook = turns[3].snapshot.committedState
        rook.apply(try XCTUnwrap(turns[3].snapshot.tentativeMove))
        let controls = LegalMoveGenerator.controlledSquares(from: square("e1"), in: rook)
        XCTAssertTrue(controls.contains(square("e5")))
        XCTAssertFalse(controls.contains(square("e7")))
        XCTAssertEqual(Piece(kind: .pawn, color: .black), rook.board[square("e5")])
    }

    func testActiveEscapeReallyForksQueenAndRookAndCannotBeTakenByKing() throws {
        let turn = try CoachingJudgmentBenchmark.corpus().allTurns[4]
        let square = CoachingPlaythroughBenchmark.square
        var state = turn.snapshot.committedState
        XCTAssertTrue(LegalMoveGenerator.controlledSquares(from: square("h6"), in: state).contains(square("g5")))
        state.apply(try XCTUnwrap(turn.snapshot.tentativeMove))
        let controls = LegalMoveGenerator.controlledSquares(from: square("f7"), in: state)
        XCTAssertTrue(controls.contains(square("d8")))
        XCTAssertTrue(controls.contains(square("h8")))
        XCTAssertEqual(Piece(kind: .queen, color: .black), state.board[square("d8")])
        XCTAssertEqual(Piece(kind: .rook, color: .black), state.board[square("h8")])
        XCTAssertFalse(LegalMoveGenerator.allLegalMoves(in: state).contains { $0.from == square("e8") && $0.to == square("f7") })
    }

    func testOptInExport() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["COACHING_JUDGMENT_BENCHMARK_OUTPUT_DIR"], !path.isEmpty else { return }
        try CoachingQualityBenchmarkExporter.write(to: URL(fileURLWithPath: path),
            sourceGitSHA: XCTUnwrap(env["COACHING_QUALITY_BENCHMARK_SOURCE_SHA"]),
            corpus: CoachingJudgmentBenchmark.corpus(), regression: true, preserveVerifiedFacts: true,
            regressionSchemaVersion: CoachingJudgmentBenchmark.manifestVersion)
    }
}
