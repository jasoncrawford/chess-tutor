import SwiftUI
import UIKit
import XCTest
@testable import ChessTutor

final class CoachFocusOverlayTests: XCTestCase {
    @MainActor
    func testRenderedArrowsHaveNoInternalWhiteSeamOrShaftBeyondTheHead() throws {
        for (from, to, kind) in [("c4", "d4", CoachFocusPath.GeometryKind.direct),
                                ("b1", "c3", .knight), ("f6", "d4", .direct)] {
            let source = sq(from), destination = sq(to)
            let geometry = BoardGuidanceGeometry(side: 640, origin: .zero, viewingAngle: .normal)
            let arrow = try XCTUnwrap(CoachArrowGeometry.make(source: source, destination: destination, kind: kind, geometry: geometry))
            let focus = CoachFocusPresentation(emphasizedSquares: [], candidateSquares: [destination],
                paths: [.init(source: source, destination: destination, role: .candidate, geometryKind: kind)], pulseID: 0)
            let renderer = ImageRenderer(content: ZStack {
                AppTheme.darkSquare
                CoachFocusOverlay(focus: focus, side: 640, origin: .zero, viewingAngle: .normal, reducesMotion: true)
            }.frame(width: 640, height: 640))
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "arrow-\(from)-\(to)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let cgImage = try XCTUnwrap(image.cgImage)
            func rgb(at point: CGPoint) throws -> [UInt8] {
                let crop = try XCTUnwrap(cgImage.cropping(to: CGRect(x: point.x * 3, y: point.y * 3, width: 1, height: 1)))
                var bytes = [UInt8](repeating: 0, count: 4)
                try bytes.withUnsafeMutableBytes { buffer in
                    let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                        bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                }
                return Array(bytes.prefix(3))
            }
            let tip = arrow.arrowhead[0]
            let base = CGPoint(x: (arrow.arrowhead[1].x + arrow.arrowhead[2].x) / 2,
                               y: (arrow.arrowhead[1].y + arrow.arrowhead[2].y) / 2)
            let length = hypot(tip.x - base.x, tip.y - base.y)
            let dx = (tip.x - base.x) / length, dy = (tip.y - base.y) / length
            // Sample the actual join, not an exact screenshot: every interior
            // point must be purple, with no white head-base crossing the shaft.
            for offset in stride(from: -2.0, through: 2.0, by: 0.25) {
                let color = try rgb(at: CGPoint(x: base.x + dx * offset, y: base.y + dy * offset))
                XCTAssertLessThan(color[0], 205, "No pale seam at the shaft/head join for \(from)-\(to)")
                XCTAssertGreaterThan(Int(color[2]) - Int(color[1]), 10, "The arrow interior should be purple")
            }
            let beyond = try rgb(at: CGPoint(x: tip.x + dx * 3, y: tip.y + dy * 3))
            let background = try rgb(at: .zero)
            for channel in 0..<3 {
                XCTAssertEqual(Int(beyond[channel]), Int(background[channel]), accuracy: 4,
                               "The shaft must not protrude past the outlined tip")
            }
            let beforeHead = arrow.points[arrow.points.count - 2]
            let shaftCenter = CGPoint(x: (beforeHead.x + base.x) / 2, y: (beforeHead.y + base.y) / 2)
            let style = CoachFocusStyle.current
            let edgeOffset = 80 * (style.arrowShaftWidthInCells / 2 + style.arrowKeylineWidthInCells / 4)
            let keyline = try rgb(at: CGPoint(x: shaftCenter.x - dy * edgeOffset, y: shaftCenter.y + dx * edgeOffset))
            XCTAssertGreaterThan(keyline[0], 220, "Retain the light exterior outline against a dark square")
            XCTAssertGreaterThan(keyline[1], 210)
        }
    }

    func testVisualArrowsPointTowardTargetAtEveryOrientationAndRevisionIsDirect() throws {
        for angle in [BoardViewingAngle.normal, .halfTurn, .clockwiseQuarterTurn, .counterclockwiseQuarterTurn] {
            let geometry = BoardGuidanceGeometry(side: 640, origin: CGPoint(x: 12, y: 20), viewingAngle: angle)
            for (from, to, kind, count) in [("g1", "f3", CoachFocusPath.GeometryKind.knight, 3),
                                           ("h3", "f3", .relocation, 2), ("c8", "c3", .direct, 2), ("e4", "e5", .direct, 2)] {
                let arrow = try XCTUnwrap(CoachArrowGeometry.make(source: sq(from), destination: sq(to), kind: kind, geometry: geometry))
                XCTAssertEqual(count, arrow.points.count)
                let target = geometry.center(of: sq(to)), tip = try XCTUnwrap(arrow.points.last)
                let style = CoachFocusStyle.current
                let largestRingRadius = 80 * (style.candidateRingScale * 1.08 / 2 + style.candidateRingKeylineWidthInCells / 2)
                XCTAssertGreaterThan(hypot(target.x - tip.x, target.y - tip.y), largestRingRadius + 80 * 0.02,
                                     "Leave a visible gap outside the destination ring, including its pulse and the arrow outline")
                XCTAssertEqual(3, arrow.arrowhead.count)
                let previous = arrow.points[arrow.points.count - 2]
                XCTAssertGreaterThan((tip.x - previous.x) * (target.x - tip.x) + (tip.y - previous.y) * (target.y - tip.y), 0)
                for point in arrow.points + arrow.arrowhead {
                    XCTAssertTrue(CGRect(x: 12, y: 20, width: 640, height: 640).contains(point))
                }
            }
            XCTAssertNil(CoachArrowGeometry.make(source: sq("e4"), destination: sq("e4"), kind: .direct, geometry: geometry))
        }
    }
    func testOpponentReplyHintUsesFullHypotheticalReplyPaths() async throws {
        let queenLoss = try await hintedOpponentReply(
            position: .exposedQueen,
            move: CoachingGoldenMoves.exposesQueen
        )
        let harmlessCheck = try await hintedOpponentReply(
            position: .harmlessCheck,
            move: CoachingGoldenMoves.developsKnight
        )

        XCTAssertEqual(queenLoss.focus.candidateSquares, [sq("d8")])
        XCTAssertEqual(queenLoss.focus.paths, [CoachFocusPath(
            source: sq("d8"),
            destination: sq("d4"),
            role: .attacker
        )])
        XCTAssertEqual(harmlessCheck.focus.candidateSquares, [sq("a8")])
        XCTAssertEqual(harmlessCheck.focus.paths, [CoachFocusPath(
            source: sq("a8"),
            destination: sq("a1"),
            role: .attacker
        )])
    }

    func testCandidatePathUsesReadableBoardGeometry() {
        let source = Square(file: .b, rank: 1)
        let destination = Square(file: .c, rank: 3)
        let geometry = BoardGuidanceGeometry(
            side: 640,
            origin: .zero,
            viewingAngle: .clockwiseQuarterTurn
        )

        let layout = CoachFocusPathLayout.make(
            from: source,
            to: destination,
            geometry: geometry
        )

        XCTAssertEqual(layout.start, geometry.center(of: source))
        XCTAssertEqual(layout.end, geometry.center(of: destination))
    }

    func testCandidatePathUsesBoardGeometryForEveryTabletopOrientation() {
        let source = Square(file: .a, rank: 8)
        let destination = Square(file: .h, rank: 1)

        for viewingAngle in [
            BoardViewingAngle.normal,
            .clockwiseQuarterTurn,
            .halfTurn,
            .counterclockwiseQuarterTurn,
        ] {
            let geometry = BoardGuidanceGeometry(
                side: 640,
                origin: CGPoint(x: 12, y: 20),
                viewingAngle: viewingAngle
            )

            let layout = CoachFocusPathLayout.make(
                from: source,
                to: destination,
                geometry: geometry
            )

            XCTAssertEqual(layout.start, geometry.center(of: source))
            XCTAssertEqual(layout.end, geometry.center(of: destination))
        }
    }

    func testReducedMotionDisablesCoachPulse() {
        XCTAssertEqual(CoachFocusMotionPolicy(reducesMotion: true).pulseScale, 1)
        XCTAssertGreaterThan(CoachFocusMotionPolicy(reducesMotion: false).pulseScale, 1)
    }

    func testCandidateHintUsesLargeContrastingKeylinedRing() {
        let style = CoachFocusStyle.current

        XCTAssertEqual(style.candidateRingScale, 0.80, accuracy: 0.001)
        XCTAssertEqual(style.candidateRingLineWidthInCells, 0.036, accuracy: 0.001)
        XCTAssertEqual(style.candidateRingKeylineWidthInCells, 0.072, accuracy: 0.001)
        XCTAssertGreaterThan(
            style.candidateRingKeylineWidthInCells,
            style.candidateRingLineWidthInCells
        )
        XCTAssertTrue(style.pathDash(for: .attacker).isEmpty)
        XCTAssertFalse(style.pathDash(for: .candidate).isEmpty)
        XCTAssertLessThan(style.pathLineWidthInCells, BoardGuidanceStyle.current.pathLineWidthInCells)
    }

    func testIdentificationInstructionBecomesBoardAccessibilityContextOnlyWhileIdentifying() {
        let identify = coachingPresentation(
            instruction: "Tap the piece that could capture it.",
            boardTask: .identify(allowsMoveRevision: false)
        )
        let move = coachingPresentation(
            instruction: "Make a move on the board.",
            boardTask: .move
        )

        XCTAssertEqual(
            CoachBoardAccessibilityContext.instruction(for: identify),
            "Tap the piece that could capture it."
        )
        XCTAssertNil(CoachBoardAccessibilityContext.instruction(for: move))
        XCTAssertNil(CoachBoardAccessibilityContext.instruction(for: nil))
    }

    private func coachingPresentation(
        instruction: String,
        boardTask: CoachingBoardTask
    ) -> CoachingPresentation {
        CoachingPresentation(
            primaryMessage: "What do you notice?",
            instruction: instruction,
            observation: nil,
            hint: nil,
            routine: [],
            actions: [],
            boardTask: boardTask,
            focus: .empty
        )
    }

    private func hintedOpponentReply(
        position: CoachingGoldenPosition,
        move: Move
    ) async throws -> CoachingPresentation {
        let interaction = CoachingInteractionSnapshot(
            selectedSquare: move.to,
            tentativeMove: move,
            positionRevision: 1
        )
        var session = CoachingSession(
            learner: .white,
            interaction: interaction,
            initialContext: .tentativeMove(origin: .fallback)
        )
        let advice = try await LocalCoachingAdvisor().advice(for: CoachingRequest(
            committedState: position.state,
            tentativeMove: move,
            learner: .white,
            positionRevision: interaction.positionRevision,
            context: .tentativeMove(origin: .fallback)
        ))
        session.receive(advice, interaction: interaction)
        session.handle(.actionChosen(.hint))
        return try XCTUnwrap(session.presentation)
    }
}
