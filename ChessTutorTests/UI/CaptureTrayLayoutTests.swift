import XCTest
@testable import ChessTutor

final class CaptureTrayLayoutTests: XCTestCase {
    func testCaptureTrayStartsWithLargePieces() {
        let layout = CaptureTrayLayout.make(for: 3, in: CGSize(width: 204, height: 85))

        XCTAssertEqual(layout.columns, 3)
        XCTAssertEqual(layout.pieceSize, 56)
    }

    func testCaptureTrayShrinksSingleRowBeforeWrapping() {
        let layout = CaptureTrayLayout.make(for: 5, in: CGSize(width: 204, height: 85))

        XCTAssertEqual(layout.columns, 5)
        XCTAssertEqual(layout.pieceSize, 37.6, accuracy: 0.01)
    }

    func testCaptureTrayWrapsToAtLeastFourColumns() {
        let layout = CaptureTrayLayout.make(for: 6, in: CGSize(width: 204, height: 85))

        XCTAssertEqual(layout.columns, 6)
        XCTAssertEqual(layout.pieceSize, 30.67, accuracy: 0.01)
    }

    func testCaptureTrayFillsRowsBeforeWrappingAgain() {
        let layout = CaptureTrayLayout.make(for: 15, in: CGSize(width: 204, height: 85))

        XCTAssertEqual(layout.columns, 8)
        XCTAssertEqual(layout.pieceSize, 22)
    }

    func testCaptureTrayGroupsDuplicatePieceKindsInFirstOccurrenceOrder() {
        let groups = CaptureTrayGroup.groups(for: [
            captured(.bishop, id: "bishop-1"),
            captured(.pawn, id: "pawn-1"),
            captured(.bishop, id: "bishop-2"),
            captured(.knight, id: "knight-1")
        ])

        XCTAssertEqual(groups.map(\.kind), [.bishop, .pawn, .knight])
        XCTAssertEqual(groups.map { $0.pieces.map(\.id) }, [
            ["bishop-1", "bishop-2"],
            ["pawn-1"],
            ["knight-1"]
        ])
    }

    func testCaptureTrayShowsPawnCountsAfterTwoPawns() {
        let groups = CaptureTrayGroup.groups(for: [
            captured(.pawn, id: "pawn-1"),
            captured(.pawn, id: "pawn-2"),
            captured(.pawn, id: "pawn-3")
        ])

        XCTAssertEqual(groups.first?.countText, "x3")
    }

    func testCaptureTrayDoesNotShowCountsForTwoPawnsOrNonPawns() {
        let twoPawnGroup = CaptureTrayGroup.groups(for: [
            captured(.pawn, id: "pawn-1"),
            captured(.pawn, id: "pawn-2")
        ])
        let rookGroup = CaptureTrayGroup.groups(for: [
            captured(.rook, id: "rook-1"),
            captured(.rook, id: "rook-2")
        ])

        XCTAssertNil(twoPawnGroup.first?.countText)
        XCTAssertNil(rookGroup.first?.countText)
    }

    private func captured(_ kind: Piece.Kind, id: String) -> CapturedPiece {
        CapturedPiece(
            id: id,
            piece: Piece(kind: kind, color: .black),
            capturedAt: Square(file: .a, rank: 1),
            state: .committed
        )
    }
}
