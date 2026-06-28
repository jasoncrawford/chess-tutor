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
}
