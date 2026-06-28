import XCTest
import UIKit
@testable import ChessTutor

final class BoardTests: XCTestCase {
    func testStartingPositionHasExpectedPieces() {
        let board = Board.startingPosition()

        XCTAssertEqual(board[Square(file: .e, rank: 1)]?.kind, .king)
        XCTAssertEqual(board[Square(file: .e, rank: 1)]?.color, .white)
        XCTAssertEqual(board[Square(file: .d, rank: 8)]?.kind, .queen)
        XCTAssertEqual(board[Square(file: .d, rank: 8)]?.color, .black)
        XCTAssertEqual(board.pieces.count, 32)
    }

    func testStartingPositionPlacesQueensOnTheirOwnColor() {
        let board = Board.startingPosition()

        XCTAssertEqual(board[Square(file: .d, rank: 1)], Piece(kind: .queen, color: .white))
        XCTAssertEqual(board[Square(file: .d, rank: 8)], Piece(kind: .queen, color: .black))
        XCTAssertEqual(board[Square(file: .e, rank: 1)], Piece(kind: .king, color: .white))
        XCTAssertEqual(board[Square(file: .e, rank: 8)], Piece(kind: .king, color: .black))
    }

    func testSquareColorsMatchConventionalChessboard() {
        XCTAssertFalse(Square(file: .a, rank: 1).isLightSquare)
        XCTAssertTrue(Square(file: .d, rank: 1).isLightSquare)
        XCTAssertFalse(Square(file: .d, rank: 8).isLightSquare)
    }

    func testSquareOffsetsRejectBoardEdges() {
        let a1 = Square(file: .a, rank: 1)

        XCTAssertNil(a1.offset(fileDelta: -1, rankDelta: 0))
        XCTAssertNil(a1.offset(fileDelta: 0, rankDelta: -1))
        XCTAssertEqual(a1.offset(fileDelta: 1, rankDelta: 1), Square(file: .b, rank: 2))
    }

    func testBoardViewingAngleKeepsThePhysicalBoardLayoutStable() {
        XCTAssertEqual(BoardViewingAngle.normal.files, Square.File.allCases)
        XCTAssertEqual(BoardViewingAngle.normal.ranks, Array((1...8).reversed()))
        XCTAssertEqual(BoardViewingAngle.normal.tableRotationDegrees, 0)
        XCTAssertEqual(BoardViewingAngle.normal.readableRotationDegrees, 0)

        XCTAssertEqual(BoardViewingAngle.halfTurn.files, Square.File.allCases)
        XCTAssertEqual(BoardViewingAngle.halfTurn.ranks, Array((1...8).reversed()))
        XCTAssertEqual(BoardViewingAngle.halfTurn.tableRotationDegrees, 180)
        XCTAssertEqual(BoardViewingAngle.halfTurn.readableRotationDegrees, -180)
    }

    func testBoardViewingAngleRotatesReadableItemsForPortraitTabletopPositions() {
        XCTAssertEqual(
            BoardViewingAngle(deviceOrientation: .portrait, baseline: .landscapeLeft),
            .clockwiseQuarterTurn
        )
        XCTAssertEqual(
            BoardViewingAngle(deviceOrientation: .portraitUpsideDown, baseline: .landscapeLeft),
            .counterclockwiseQuarterTurn
        )

        XCTAssertEqual(BoardViewingAngle.clockwiseQuarterTurn.files, Square.File.allCases)
        XCTAssertEqual(BoardViewingAngle.clockwiseQuarterTurn.ranks, Array((1...8).reversed()))
        XCTAssertEqual(BoardViewingAngle.clockwiseQuarterTurn.tableRotationDegrees, 90)
        XCTAssertEqual(BoardViewingAngle.clockwiseQuarterTurn.readableRotationDegrees, -90)
        XCTAssertTrue(BoardViewingAngle.clockwiseQuarterTurn.presentsSidebarSegmentsHorizontally)
        XCTAssertEqual(
            BoardViewingAngle.clockwiseQuarterTurn.sidebarSegmentsInTabletopOrder,
            [.newGame, .capturedPieces, .messageAndDone]
        )
        XCTAssertEqual(BoardViewingAngle.counterclockwiseQuarterTurn.tableRotationDegrees, -90)
        XCTAssertEqual(BoardViewingAngle.counterclockwiseQuarterTurn.readableRotationDegrees, 90)
        XCTAssertTrue(BoardViewingAngle.counterclockwiseQuarterTurn.presentsSidebarSegmentsHorizontally)
        XCTAssertEqual(
            BoardViewingAngle.counterclockwiseQuarterTurn.sidebarSegmentsInTabletopOrder,
            [.messageAndDone, .capturedPieces, .newGame]
        )
    }

    func testBoardViewingAngleCanInitializeFromInterfaceOrientationAtLaunch() {
        XCTAssertEqual(
            BoardViewingAngle(interfaceOrientation: .portrait, baseline: .landscapeLeft),
            .clockwiseQuarterTurn
        )
        XCTAssertEqual(
            BoardViewingAngle(interfaceOrientation: .landscapeRight, baseline: .landscapeLeft),
            .halfTurn
        )
    }

    func testBoardViewingAngleTreatsLandscapeAsBaselineNotSideways() {
        XCTAssertEqual(
            BoardViewingAngle(deviceOrientation: .landscapeLeft, baseline: .landscapeLeft),
            .normal
        )
        XCTAssertEqual(
            BoardViewingAngle(deviceOrientation: .landscapeRight, baseline: .landscapeLeft),
            .halfTurn
        )
        XCTAssertFalse(BoardViewingAngle.normal.presentsSidebarSegmentsHorizontally)
        XCTAssertFalse(BoardViewingAngle.halfTurn.presentsSidebarSegmentsHorizontally)
        XCTAssertEqual(
            BoardViewingAngle.normal.sidebarSegmentsInTabletopOrder,
            [.messageAndDone, .capturedPieces, .newGame]
        )
        XCTAssertEqual(
            BoardViewingAngle.halfTurn.sidebarSegmentsInTabletopOrder,
            [.newGame, .capturedPieces, .messageAndDone]
        )
    }

    func testBoardViewingAngleChoosesNearestEquivalentRotationForAnimation() {
        XCTAssertEqual(
            BoardViewingAngle.counterclockwiseQuarterTurn.tableRotationDegrees(closestTo: 180),
            270
        )
        XCTAssertEqual(
            BoardViewingAngle.counterclockwiseQuarterTurn.tableRotationDegrees(closestTo: 0),
            -90
        )
        XCTAssertEqual(
            BoardViewingAngle.normal.tableRotationDegrees(closestTo: 270),
            360
        )
    }
}
