import XCTest
@testable import ChessTutor

final class MoveHistoryFormatterTests: XCTestCase {
    func testGroupsHalfMovesIntoNumberedTurns() {
        let moves = [
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
            Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 5)),
            Move(from: Square(file: .g, rank: 1), to: Square(file: .f, rank: 3)),
        ]

        let rows = MoveHistoryFormatter.rows(for: moves)

        XCTAssertEqual(rows, [
            MoveHistoryRow(number: 1, whiteMove: "e4", blackMove: "e5"),
            MoveHistoryRow(number: 2, whiteMove: "Nf3", blackMove: nil),
        ])
    }

    func testDisplayTextPresentsOneLinePerFullMove() {
        let moves = [
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
            Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 5)),
            Move(from: Square(file: .g, rank: 1), to: Square(file: .f, rank: 3)),
        ]

        let displayLines = MoveHistoryFormatter.rows(for: moves).map(\.displayText)

        XCTAssertEqual(displayLines, [
            "1. e4  e5",
            "2. Nf3",
        ])
    }

    func testUsesPieceLettersAndCaptureMarkers() {
        let moves = [
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
            Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 5)),
            Move(from: Square(file: .d, rank: 1), to: Square(file: .h, rank: 5)),
            Move(from: Square(file: .b, rank: 8), to: Square(file: .c, rank: 6)),
            Move(from: Square(file: .h, rank: 5), to: Square(file: .e, rank: 5)),
        ]

        let displayLines = MoveHistoryFormatter.rows(for: moves).map(\.displayText)

        XCTAssertEqual(displayLines, [
            "1. e4  e5",
            "2. Qh5  Nc6",
            "3. Qxe5+",
        ])
    }

    func testIncludesCastlingMarker() {
        let moves = [
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
            Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 5)),
            Move(from: Square(file: .g, rank: 1), to: Square(file: .f, rank: 3)),
            Move(from: Square(file: .b, rank: 8), to: Square(file: .c, rank: 6)),
            Move(from: Square(file: .f, rank: 1), to: Square(file: .c, rank: 4)),
            Move(from: Square(file: .g, rank: 8), to: Square(file: .f, rank: 6)),
            Move(from: Square(file: .e, rank: 1), to: Square(file: .g, rank: 1), special: .castleKingside),
        ]

        let rows = MoveHistoryFormatter.rows(for: moves)

        XCTAssertEqual(rows.last, MoveHistoryRow(number: 4, whiteMove: "O-O", blackMove: nil))
    }

    func testFormatsEnPassantAsPawnCapture() {
        let moves = [
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
            Move(from: Square(file: .a, rank: 7), to: Square(file: .a, rank: 6)),
            Move(from: Square(file: .e, rank: 4), to: Square(file: .e, rank: 5)),
            Move(from: Square(file: .d, rank: 7), to: Square(file: .d, rank: 5)),
            Move(from: Square(file: .e, rank: 5), to: Square(file: .d, rank: 6), special: .enPassant),
        ]

        let rows = MoveHistoryFormatter.rows(for: moves)

        XCTAssertEqual(rows.last, MoveHistoryRow(number: 3, whiteMove: "exd6", blackMove: nil))
    }
}
