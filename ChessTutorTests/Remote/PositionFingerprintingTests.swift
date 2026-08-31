import XCTest
@testable import ChessTutor

final class PositionFingerprintingTests: XCTestCase {
    func testStartingPositionFingerprintIsDeterministic() {
        let first = PositionFingerprinting.fingerprint(for: .startingPosition())
        let second = PositionFingerprinting.fingerprint(for: .startingPosition())

        XCTAssertEqual(first, second)
    }

    func testFingerprintChangesAfterMove() {
        var state = GameState.startingPosition()
        let before = PositionFingerprinting.fingerprint(for: state)

        state.apply(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)))
        let after = PositionFingerprinting.fingerprint(for: state)

        XCTAssertNotEqual(before, after)
    }

    func testFingerprintIncludesSideToMove() {
        let whiteToMove = GameState.startingPosition()
        var blackToMove = GameState.startingPosition()
        blackToMove.sideToMove = .black

        XCTAssertNotEqual(
            PositionFingerprinting.fingerprint(for: whiteToMove),
            PositionFingerprinting.fingerprint(for: blackToMove)
        )
    }

    func testLocalGuidanceStateDoesNotChangePositionFingerprint() {
        let session = GameSession()
        let before = PositionFingerprinting.fingerprint(for: session.state)

        session.select(Square(file: .e, rank: 2))
        let after = PositionFingerprinting.fingerprint(for: session.state)

        XCTAssertEqual(after, before)
    }
}
