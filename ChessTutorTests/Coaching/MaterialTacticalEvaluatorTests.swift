import XCTest
@testable import ChessTutor

final class MaterialTacticalEvaluatorTests: XCTestCase {
    private let evaluator = MaterialTacticalEvaluator()

    func testUsesBeginnerPieceValues() {
        XCTAssertEqual(evaluator.pieceValue(.pawn), 1)
        XCTAssertEqual(evaluator.pieceValue(.knight), 3)
        XCTAssertEqual(evaluator.pieceValue(.bishop), 3)
        XCTAssertEqual(evaluator.pieceValue(.rook), 5)
        XCTAssertEqual(evaluator.pieceValue(.queen), 9)
        XCTAssertNil(evaluator.pieceValue(.king))
    }

    func testPawnTakingDefendedBishopHasNetGainTwo() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let recapturer = Square(file: .e, rank: 6)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .pawn, color: .white),
                target: Piece(kind: .bishop, color: .black),
                recapturer: Piece(kind: .pawn, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(
                for: Move(from: attacker, to: target),
                in: state
            )
        )

        XCTAssertEqual(estimate.capturedSquare, target)
        XCTAssertEqual(estimate.netGainForMover, 2)
        XCTAssertEqual(estimate.immediateRecapture?.from, recapturer)
        XCTAssertEqual(estimate.immediateRecapture?.to, target)
    }

    func testUndefendedCaptureKeepsCapturedPieceValue() throws {
        let attacker = Square(file: .a, rank: 2)
        let target = Square(file: .a, rank: 7)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .rook, color: .white),
                target: Piece(kind: .knight, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(for: Move(from: attacker, to: target), in: state)
        )

        XCTAssertNil(estimate.immediateRecapture)
        XCTAssertEqual(estimate.netGainForMover, 3)
    }

    func testQueenTakingPawnAndBeingRecapturedHasNetLossEight() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let recapturer = Square(file: .f, rank: 6)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .queen, color: .white),
                target: Piece(kind: .pawn, color: .black),
                recapturer: Piece(kind: .knight, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(for: Move(from: attacker, to: target), in: state)
        )

        XCTAssertEqual(estimate.immediateRecapture, Move(from: recapturer, to: target))
        XCTAssertEqual(estimate.netGainForMover, -8)
    }

    func testMultipleLegalRecapturesUseStableMoveOrdering() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let earlierRecapturer = Square(file: .f, rank: 6)
        let laterRecapturer = Square(file: .d, rank: 8)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .bishop, color: .white),
                target: Piece(kind: .pawn, color: .black),
                earlierRecapturer: Piece(kind: .knight, color: .black),
                laterRecapturer: Piece(kind: .queen, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(for: Move(from: attacker, to: target), in: state)
        )

        XCTAssertEqual(estimate.immediateRecapture, Move(from: earlierRecapturer, to: target))
    }

    func testPinnedRecapturerDoesNotReduceEstimatedGain() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let pinnedRecapturer = Square(file: .f, rank: 6)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .f, rank: 1): Piece(kind: .rook, color: .white),
                attacker: Piece(kind: .bishop, color: .white),
                target: Piece(kind: .pawn, color: .black),
                pinnedRecapturer: Piece(kind: .knight, color: .black),
                Square(file: .f, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(for: Move(from: attacker, to: target), in: state)
        )

        XCTAssertNil(estimate.immediateRecapture)
        XCTAssertEqual(estimate.netGainForMover, 1)
    }

    func testEnPassantReportsPawnSquareInsteadOfLandingSquare() throws {
        let attacker = Square(file: .e, rank: 5)
        let capturedPawn = Square(file: .d, rank: 5)
        let landingSquare = Square(file: .d, rank: 6)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .pawn, color: .white),
                capturedPawn: Piece(kind: .pawn, color: .black),
            ],
            enPassantTarget: landingSquare
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(
                for: Move(from: attacker, to: landingSquare, special: .enPassant),
                in: state
            )
        )

        XCTAssertEqual(estimate.capturedSquare, capturedPawn)
        XCTAssertNotEqual(estimate.capturedSquare, estimate.move.to)
        XCTAssertEqual(estimate.netGainForMover, 1)
    }

    func testPromotionCaptureUsesPromotedPieceValueWhenRecaptured() throws {
        let attacker = Square(file: .c, rank: 7)
        let target = Square(file: .d, rank: 8)
        let recapturer = Square(file: .d, rank: 7)
        let promotion = Move(from: attacker, to: target, special: .promotion(.queen))
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .pawn, color: .white),
                target: Piece(kind: .bishop, color: .black),
                recapturer: Piece(kind: .rook, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(evaluator.captureEstimate(for: promotion, in: state))

        XCTAssertEqual(estimate.immediateRecapture, Move(from: recapturer, to: target))
        XCTAssertEqual(estimate.netGainForMover, -6)
    }
}
