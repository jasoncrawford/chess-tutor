import CoreGraphics
import XCTest
@testable import ChessTutor

final class BoardGuidanceStyleTests: XCTestCase {
    func testContestedCoverageProducesTwoDistinctNonoverlappingMarkers() {
        let markers = CoveragePipLayout.markers(
            showsSideToMove: true,
            showsOtherSide: true,
            cellSize: 84
        )

        XCTAssertEqual(markers.map(\.shape), [.circle, .diamond])
        XCTAssertFalse(markers[0].frame.intersects(markers[1].frame))
    }

    func testSingleCoverageMarkersKeepTheirShapeAndStablePosition() {
        let sideToMove = CoveragePipLayout.markers(
            showsSideToMove: true,
            showsOtherSide: false,
            cellSize: 84
        )
        let otherSide = CoveragePipLayout.markers(
            showsSideToMove: false,
            showsOtherSide: true,
            cellSize: 84
        )

        XCTAssertEqual(sideToMove.map(\.shape), [.circle])
        XCTAssertEqual(otherSide.map(\.shape), [.diamond])
        XCTAssertEqual(
            sideToMove[0].frame,
            CoveragePipLayout.markers(
                showsSideToMove: true,
                showsOtherSide: true,
                cellSize: 84
            )[0].frame
        )
    }

    func testTrajectoryLayoutKeepsArrowheadSmallRelativeToBoardCell() {
        let layout = GuidancePathLayout.make(
            from: CGPoint(x: 42, y: 42),
            to: CGPoint(x: 210, y: 42),
            cellSize: 84
        )

        XCTAssertLessThanOrEqual(layout.arrowheadLength, 84 * 0.16)
        XCTAssertGreaterThan(layout.shaftLength, layout.arrowheadLength * 4)
    }

    func testTrajectoryStopsClearOfPieceCenters() {
        let source = CGPoint(x: 42, y: 42)
        let destination = CGPoint(x: 126, y: 42)

        let layout = GuidancePathLayout.make(
            from: source,
            to: destination,
            cellSize: 84
        )

        XCTAssertGreaterThan(layout.start.x, source.x)
        XCTAssertLessThan(layout.tip.x, destination.x)
        XCTAssertGreaterThan(layout.shaftLength, 0)
        XCTAssertFalse(layout.arrowhead.contains(layout.start))
    }

    func testBoardGuidanceGeometryMapsSquaresToCellCenters() {
        let geometry = BoardGuidanceGeometry(
            side: 672,
            origin: CGPoint(x: 12, y: 20),
            viewingAngle: .normal
        )

        XCTAssertEqual(
            geometry.center(of: Square(file: .a, rank: 8)),
            CGPoint(x: 54, y: 62)
        )
        XCTAssertEqual(
            geometry.center(of: Square(file: .h, rank: 1)),
            CGPoint(x: 642, y: 650)
        )
    }
}
