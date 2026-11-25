import Foundation
import XCTest
@testable import ChessTutor

final class ModelCoachingVisualTurnTests: XCTestCase {
    func testSharedVisualContractCases() throws {
        let fixture = try fixtures()
        let requests = try XCTUnwrap(fixture["requests"] as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        for test in cases {
            let id = try XCTUnwrap(test["id"] as? String)
            let context = try XCTUnwrap(test["context"] as? String)
            let request = try JSONDecoder().decode(ModelCoachingNeutralRequest.self,
                from: JSONSerialization.data(withJSONObject: XCTUnwrap(requests[context])))
            let data = try JSONSerialization.data(withJSONObject: XCTUnwrap(test["turn"]))
            if test["valid"] as? Bool == true {
                let turn = try ModelCoachingVisualTurnDecoder.decodeAndValidate(data, request: request)
                XCTAssertNotNil(turn.visualContent, id)
                XCTAssertEqual(turn.message, turn.visualContent?.plainText, id)
            } else {
                XCTAssertThrowsError(try ModelCoachingVisualTurnDecoder.decodeAndValidate(data, request: request), id)
            }
        }
    }

    func testRenderedMessagePreservesSpacesAndPunctuation() {
        let content = ModelCoachingVisualContent(runs: [
            .piece(text: "This rook", square: "b8"), .text(" attacks "),
            .piece(text: "your knight", square: "b1"), .text("."),
        ], visuals: [])
        XCTAssertEqual("This rook attacks your knight.", content.plainText)
    }

    func testDuplicateKeysAreRejectedBeforeDecoding() throws {
        let request = ModelCoachingNeutralRequestBuilder.build(snapshot: .init(
            committedState: .startingPosition(), learner: .white, positionRevision: 0,
            selectedSquare: nil, tentativeMove: nil,
            latestEvent: .init(sequence: 1, kind: .helpOpened, referencedIDs: []), episodeEvents: []), requestID: "test")
        let raw = #"{"message":[{"type":"text","text":"Look","text":"Again"}],"actions":[],"visuals":[],"expects":"stageMove"}"#
        XCTAssertThrowsError(try ModelCoachingVisualTurnDecoder.decodeAndValidate(Data(raw.utf8), request: request))
    }

    func testDraftReferencesUseRealDisplayedBoardAndCanonicalRevision() throws {
        let state = GameState.startingPosition()
        let move = Move(from: Square(file: .g, rank: 1), to: Square(file: .h, rank: 3))
        let request = ModelCoachingNeutralRequestBuilder.build(snapshot: .init(
            committedState: state, learner: .white, positionRevision: 0,
            selectedSquare: move.to, tentativeMove: move,
            latestEvent: .init(sequence: 2, kind: .actionChosen, referencedIDs: ["action:hint"]), episodeEvents: []), requestID: "draft")
        for (square, valid) in [("h3", true), ("g1", false)] {
            let raw = "{\"message\":[{\"type\":\"piece\",\"text\":\"Your knight\",\"square\":\"\(square)\"}],\"actions\":[],\"visuals\":[{\"type\":\"move\",\"from\":\"g1\",\"to\":\"f3\"}],\"expects\":\"chooseWhetherToPlay\"}"
            if valid { XCTAssertNoThrow(try ModelCoachingVisualTurnDecoder.decodeAndValidate(Data(raw.utf8), request: request)) }
            else { XCTAssertThrowsError(try ModelCoachingVisualTurnDecoder.decodeAndValidate(Data(raw.utf8), request: request)) }
        }
    }

    func testSpecialMoveReferencesFollowTheActualDisplayedPieces() throws {
        let cases: [(GameState, Move, String, String, String)] = [
            (GameState(board: Board(pieces: [
                sq("a1"): Piece(kind: .king, color: .white), sq("h8"): Piece(kind: .king, color: .black),
                sq("e5"): Piece(kind: .pawn, color: .white), sq("d5"): Piece(kind: .pawn, color: .black),
            ]), sideToMove: .white, enPassantTarget: sq("d6")),
             Move(from: sq("e5"), to: sq("d6"), special: .enPassant), "d6", "d5", "pawn"),
            (GameState(board: Board(pieces: [
                sq("h1"): Piece(kind: .king, color: .white), sq("h8"): Piece(kind: .king, color: .black),
                sq("a7"): Piece(kind: .pawn, color: .white),
            ]), sideToMove: .white),
             Move(from: sq("a7"), to: sq("a8"), special: .promotion(.queen)), "a8", "a7", "queen"),
            (GameState(board: Board(pieces: [
                sq("a1"): Piece(kind: .king, color: .white), sq("h8"): Piece(kind: .king, color: .black),
                sq("d1"): Piece(kind: .rook, color: .white), sq("d5"): Piece(kind: .knight, color: .black),
            ]), sideToMove: .white), Move(from: sq("d1"), to: sq("d5")), "d5", "d1", "rook"),
        ]
        for (state, move, present, absent, kind) in cases {
            XCTAssertTrue(LegalMoveGenerator.allLegalMoves(in: state).contains(move))
            let request = ModelCoachingNeutralRequestBuilder.build(snapshot: .init(
                committedState: state, learner: .white, positionRevision: 0,
                selectedSquare: move.to, tentativeMove: move,
                latestEvent: .init(sequence: 1, kind: .moveStaged, referencedIDs: []), episodeEvents: []), requestID: "special")
            XCTAssertEqual(kind, request.tentativePosition?.pieces.first { $0.square == present }?.kind)
            for (square, valid) in [(present, true), (absent, false)] {
                let raw: [String: Any] = ["message": [["type": "piece", "text": "Your piece", "square": square]],
                    "visuals": [], "actions": [], "expects": "chooseWhetherToPlay"]
                let data = try JSONSerialization.data(withJSONObject: raw)
                if valid { XCTAssertNoThrow(try ModelCoachingVisualTurnDecoder.decodeAndValidate(data, request: request)) }
                else { XCTAssertThrowsError(try ModelCoachingVisualTurnDecoder.decodeAndValidate(data, request: request)) }
            }
        }
    }

    private func sq(_ name: String) -> Square {
        Square(file: Square.File(rawValue: Int(name.utf8.first!) - 96)!, rank: Int(String(name.last!))!)
    }

    private func fixtures() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root
            .appendingPathComponent("Tools/CoachingEval/fixtures/visual-coaching-validation-v1.json"))) as? [String: Any])
    }
}
