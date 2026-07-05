import XCTest
@testable import ChessTutor

final class RemoteMoveCodecTests: XCTestCase {
    func testEncodesNormalMove() throws {
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))

        let encoded = RemoteMoveCodec.encode(move)

        XCTAssertEqual(encoded.from, "e2")
        XCTAssertEqual(encoded.to, "e4")
        XCTAssertEqual(encoded.special, .none)
    }

    func testRoundTripsPromotionMove() throws {
        let move = Move(
            from: Square(file: .e, rank: 7),
            to: Square(file: .e, rank: 8),
            special: .promotion(.queen)
        )

        let encoded = RemoteMoveCodec.encode(move)
        let decoded = try RemoteMoveCodec.decode(encoded)

        XCTAssertEqual(decoded, move)
    }

    func testDecodingRejectsInvalidSquare() {
        let encoded = RemoteEncodedMove(from: "i2", to: "e4", special: .none)

        XCTAssertThrowsError(try RemoteMoveCodec.decode(encoded)) { error in
            XCTAssertEqual(error as? RemoteMoveCodec.Error, .invalidSquare("i2"))
        }
    }
}
