import XCTest
@testable import ChessTutor

final class CaptureTrayLayoutTests: XCTestCase {
    func testCaptureTrayStartsWithLargePieces() {
        let layout = CaptureTrayLayout.make(for: 3, in: CGSize(width: 194, height: 73))

        XCTAssertEqual(layout.columns, 3)
        XCTAssertEqual(layout.pieceSize, 56)
    }

    func testCaptureTrayShrinksSingleRowBeforeWrapping() {
        let layout = CaptureTrayLayout.make(for: 4, in: CGSize(width: 194, height: 73))

        XCTAssertEqual(layout.columns, 4)
        XCTAssertEqual(layout.pieceSize, 45.5)
    }

    func testCaptureTrayWrapsToTwoRowsWhenSingleRowWouldGetTooSmall() {
        let layout = CaptureTrayLayout.make(for: 5, in: CGSize(width: 194, height: 73))

        XCTAssertEqual(layout.columns, 3)
        XCTAssertEqual(layout.pieceSize, 34.5)
    }
}
