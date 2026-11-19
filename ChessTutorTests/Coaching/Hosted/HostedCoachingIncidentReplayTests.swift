import Foundation
import XCTest
@testable import ChessTutor

final class HostedCoachingIncidentReplayTests: XCTestCase {
    // The retained production trace's complete move history, not model-authored facts.
    func testNovember18TimeoutPositionCanBeReplayedAndExported() throws {
        let notation = "Nf3 e6 e4 Nc6 Bc4 Bc5 O-O Nf6 d3 Ng4 Bg5 f6 Bf4 d5 d4 dxc4 dxc5 O-O Nc3 e5 Bd2 Be6 h3 Nh6 Nd5 g5 Be3 f5 Nd2 f4 Bd4 Nxd4 Nxc4 g4 Nxe5 Nhf5 hxg4 h5 gxf5 Rf6 Qxd4 Bxd5 exd5 Rxf5 Ng6 f3".split(separator: " ").map(String.init)
        var state = GameState.startingPosition()
        for san in notation {
            let matches = LegalMoveGenerator.allLegalMoves(in: state).filter {
                MoveHistoryFormatter.notation(for: $0, in: state) == san
            }
            XCTAssertEqual(matches.count, 1, "Ambiguous or illegal recorded move: \(san)")
            state.apply(try XCTUnwrap(matches.first))
        }
        XCTAssertEqual(ModelCoachingPositionEncoder.fen(for: state),
                       "r2q2k1/ppp5/6N1/2PP1r1p/3Q4/5p2/PPP2PP1/R4RK1 w - - 0 24")
        let opened = ModelCoachingNeutralEpisodeEvent(sequence: 1, kind: .helpOpened, referencedIDs: [])
        let request = ModelCoachingNeutralRequestBuilder.build(snapshot: ModelCoachingNeutralSnapshot(
            committedState: state, learner: .white, positionRevision: 46,
            selectedSquare: nil, tentativeMove: nil, latestEvent: opened, episodeEvents: [opened]
        ), requestID: "incident-replay-20261118")
        XCTAssertEqual(request.gameHistory.map(\.displayNotation), notation)
        // Opt-in diagnostic artifact: no API call or secret access in XCTest.
        if let path = ProcessInfo.processInfo.environment["COACHING_INCIDENT_REQUEST_PATH"], !path.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(request).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}
