import SwiftUI
import XCTest
@testable import ChessTutor

final class CoachingPanelLayoutTests: XCTestCase {
    @MainActor
    func testCoachingFeedbackRendersAtBodySizeAndStillScalesWithDynamicType() throws {
        let standard = try renderedTextLineHeights(dynamicTypeSize: .large)
        let accessible = try renderedTextLineHeights(dynamicTypeSize: .accessibility3)

        // Use identical copy in the feedback and instruction so their actual
        // rendered glyph heights reveal an accidental headline-sized response.
        XCTAssertEqual(standard.count, 2)
        XCTAssertEqual(accessible.count, 2)
        guard standard.count == 2, accessible.count == 2 else { return }
        XCTAssertEqual(standard[0], standard[1], accuracy: 1)
        XCTAssertEqual(accessible[0], accessible[1], accuracy: 1)
        XCTAssertGreaterThan(accessible[0], standard[0])
    }

    @MainActor
    private func renderedTextLineHeights(dynamicTypeSize: DynamicTypeSize) throws -> [Double] {
        let presentation = CoachingPresentation(
            primaryMessage: "A safe pawn.",
            instruction: "A safe pawn.",
            hint: nil,
            routine: [],
            actions: [],
            boardTask: .none,
            focus: .empty
        )
        let panel = CoachingPanelView(
            session: GameSession(),
            presentation: presentation,
            layout: CoachingPanelLayout(
                tabletopRegionSize: CGSize(width: 260, height: 446),
                physicalRegionSize: CGSize(width: 260, height: 446),
                physicalAxis: .vertical
            ),
            readableRotationDegrees: 0,
            onCommittedMove: { _ in }
        )
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\.colorScheme, .light)
        .background(Color.white)
        let renderer = ImageRenderer(content: panel)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        // Only inspect the conversation at the top, excluding the divider below.
        var lineHeights: [Double] = []
        var inLine = false
        for y in 0..<min(height, 160) {
            let hasInk = (0..<width).contains { x in
                let offset = (y * width + x) * 4
                return bytes[offset] < 150 && bytes[offset + 1] < 150
                    && bytes[offset + 2] < 150
            }
            if hasInk {
                if !inLine { lineHeights.append(0) }
                lineHeights[lineHeights.count - 1] += 1
            }
            inLine = hasInk
        }
        return lineHeights
    }

    func testVerticalCoachingRegionSpansMessageAndSelectedSlots() {
        let sidebar = SidebarColumnLayout.make(for: 760, presentation: .verticalColumn)
        let layout = CoachingPanelLayout.make(sidebar: sidebar)

        XCTAssertEqual(
            layout.tabletopRegionSize.height,
            sidebar.size(for: .messageAndDone).height
                + SidebarColumnLayout.segmentSpacing
                + sidebar.size(for: .selectedPiece).height,
            accuracy: 0.01
        )
        XCTAssertEqual(layout.physicalRegionSize, layout.tabletopRegionSize)
        XCTAssertEqual(layout.physicalAxis, .vertical)
        XCTAssertEqual(sidebar.size(for: .capturedPieces).height, 255.36, accuracy: 0.01)
    }

    func testHorizontalCoachingRegionUsesTwoAdjacentSlots() {
        let sidebar = SidebarColumnLayout.make(for: 760, presentation: .horizontalSegments)
        let segment = sidebar.size(for: .selectedPiece)
        let layout = CoachingPanelLayout.make(sidebar: sidebar)

        XCTAssertEqual(
            layout.tabletopRegionSize.height,
            segment.height * 2 + SidebarColumnLayout.segmentSpacing,
            accuracy: 0.01
        )
        XCTAssertEqual(
            layout.physicalRegionSize.width,
            segment.width * 2 + SidebarColumnLayout.segmentSpacing,
            accuracy: 0.01
        )
        XCTAssertEqual(layout.physicalRegionSize.height, segment.height, accuracy: 0.01)
        XCTAssertEqual(
            layout.tabletopContentSize,
            CGSize(
                width: layout.tabletopRegionSize.width - 32,
                height: layout.tabletopRegionSize.height - 32
            )
        )
        XCTAssertEqual(
            layout.physicalContentSize,
            CGSize(
                width: layout.physicalRegionSize.width - 32,
                height: layout.physicalRegionSize.height - 32
            )
        )
        XCTAssertEqual(layout.physicalAxis, .horizontal)
        XCTAssertTrue(sidebar.showsCapturedPanelUtilityFooter)
    }

    func testCoachingRegionsKeepCapturedPiecesFirstInReversedTabletopOrder() {
        XCTAssertEqual(
            CoachingPanelLayout.sidebarRegions(
                inTabletopOrder: BoardViewingAngle.clockwiseQuarterTurn.sidebarSegmentsInTabletopOrder
            ),
            [.capturedPieces, .coaching]
        )
        XCTAssertEqual(
            CoachingPanelLayout.sidebarRegions(
                inTabletopOrder: BoardViewingAngle.halfTurn.sidebarSegmentsInTabletopOrder
            ),
            [.capturedPieces, .coaching]
        )
    }

    func testCoachingRegionsKeepCapturedPiecesLastInForwardTabletopOrder() {
        XCTAssertEqual(
            CoachingPanelLayout.sidebarRegions(
                inTabletopOrder: BoardViewingAngle.normal.sidebarSegmentsInTabletopOrder
            ),
            [.coaching, .capturedPieces]
        )
        XCTAssertEqual(
            CoachingPanelLayout.sidebarRegions(
                inTabletopOrder: BoardViewingAngle.counterclockwiseQuarterTurn.sidebarSegmentsInTabletopOrder
            ),
            [.coaching, .capturedPieces]
        )
    }

    func testPhysicalAxisSelectsCompactPanelComposition() {
        let tall = CoachingPanelLayout.make(
            sidebar: .make(for: 760, presentation: .verticalColumn)
        )
        let wide = CoachingPanelLayout.make(
            sidebar: .make(for: 760, presentation: .horizontalSegments)
        )

        XCTAssertEqual(tall.composition, .tall)
        XCTAssertEqual(wide.composition, .wide)
        XCTAssertEqual(tall.composition.routineTabletopAxis, .horizontal)
        XCTAssertEqual(wide.composition.routineTabletopAxis, .vertical)
        XCTAssertEqual(tall.composition.actionTabletopAxis, .vertical)
        XCTAssertEqual(wide.composition.actionTabletopAxis, .horizontal)
    }

    func testPermanentUATFixtureSizesExerciseBothPhysicalCompositions() {
        let tall = CoachingPanelLayout(
            tabletopRegionSize: CGSize(width: 260, height: 446),
            physicalRegionSize: CGSize(width: 260, height: 446),
            physicalAxis: .vertical
        )
        let wide = CoachingPanelLayout(
            tabletopRegionSize: CGSize(width: 246.67, height: 503.34),
            physicalRegionSize: CGSize(width: 503.34, height: 246.67),
            physicalAxis: .horizontal
        )

        XCTAssertEqual(tall.composition, .tall)
        XCTAssertEqual(tall.tabletopContentSize, CGSize(width: 228, height: 414))
        XCTAssertEqual(wide.composition, .wide)
        XCTAssertEqual(wide.physicalContentSize, CGSize(width: 471.34, height: 214.67))
    }

    func testPermanentAccessibilityFixtureCoversBothCompactTurnsInEveryRotation() {
        XCTAssertEqual(
            CoachingPanelAccessibilityFixtureTurn.allCases,
            [.compactNoObservation, .compactWithObservation]
        )

        for turn in CoachingPanelAccessibilityFixtureTurn.allCases {
            let configurations: [CoachingPanelAccessibilityFixtureConfiguration] = [
                .tall(turn),
                .clockwiseQuarterTurn(turn),
                .counterclockwiseQuarterTurn(turn),
            ]
            XCTAssertEqual(configurations.map(\.composition), [.tall, .wide, .wide])
            XCTAssertEqual(configurations.map(\.tableRotationDegrees), [0, 90, -90])
            XCTAssertEqual(configurations.map(\.turn), [turn, turn, turn])
        }
    }

    func testAuthoredActionOrderAndProminenceReachPanelUnchanged() {
        let presentation = LocalCoachingExplanationSource().presentation(
            for: coachingContext(
                prompt: .safeLocate,
                actions: [.noAnswer, .hint, .stop]
            )
        )

        XCTAssertEqual(presentation.actions.map(\.action), [.noAnswer, .hint, .stop])
        XCTAssertEqual(presentation.actions.map(\.prominence), [.primary, .secondary, .quiet])
    }

    func testFeedbackResponseKeepsCurrentAskAvailableToBothPanelCompositions() {
        let presentation = LocalCoachingExplanationSource().presentation(
            for: coachingContext(
                prompt: .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
                feedback: .blockedWakePiece(piece: .rook, blocker: .pawn),
                actions: [.hint, .stop]
            )
        )
        let compositions = [
            CoachingPanelLayout.make(sidebar: .make(for: 760, presentation: .verticalColumn)),
            CoachingPanelLayout.make(sidebar: .make(for: 760, presentation: .horizontalSegments)),
        ].map(\.composition)

        XCTAssertEqual(compositions, [.tall, .wide])
        XCTAssertEqual(
            presentation.observation,
            "Your pawn blocks that rook."
        )
        XCTAssertEqual(
            presentation.primaryMessage,
            "A center pawn or knight is a simple way to start."
        )
        XCTAssertEqual(
            presentation.instruction,
            "Tap a center pawn or knight."
        )
    }

    func testCompletionKeepsDoneKeepLookingAndStopActions() {
        let presentation = LocalCoachingExplanationSource().presentation(
            for: coachingContext(
                prompt: .complete(origin: .wake, idea: .develops(piece: .knight)),
                actions: [.done, .keepLooking, .stop]
            )
        )

        XCTAssertEqual(presentation.actions.map(\.action), [.done, .keepLooking, .stop])
        XCTAssertEqual(presentation.actions.map(\.prominence), [.primary, .secondary, .quiet])
    }

    func testActiveCoachingPresentationAlwaysRetainsAuthoredStopAction() {
        let interaction = CoachingInteractionSnapshot(
            selectedSquare: nil,
            tentativeMove: nil,
            positionRevision: CoachingTestFixtures.startingPositionAdvice
                .evaluation.request.positionRevision
        )
        var session = CoachingSession(
            learner: .white,
            interaction: interaction,
            initialContext: .start
        )
        session.receive(
            CoachingTestFixtures.startingPositionAdvice,
            interaction: interaction
        )

        XCTAssertTrue(session.presentation?.actions.contains { $0.action == .stop } == true)
    }

    func testOnlyDoneRoutesReturnedMoveToCommitCallback() {
        let move = Move(
            from: Square(file: .e, rank: 2),
            to: Square(file: .e, rank: 4)
        )

        XCTAssertEqual(CoachingActionRouting.committedMove(for: .done, returnedMove: move), move)
        XCTAssertNil(CoachingActionRouting.committedMove(for: .keepLooking, returnedMove: move))
        XCTAssertNil(CoachingActionRouting.committedMove(for: .stop, returnedMove: move))
        XCTAssertNil(CoachingActionRouting.committedMove(for: .done, returnedMove: nil))
    }

    private func coachingContext(
        prompt: CoachingPrompt,
        feedback: CoachingFeedback? = nil,
        actions: [CoachingAction]
    ) -> CoachingPresentationContext {
        CoachingPresentationContext(
            prompt: prompt,
            feedback: feedback,
            learner: .white,
            hint: nil,
            missesAtCurrentLevel: 0,
            routine: [.safeCleared, .takeCleared, .wakeCurrent],
            actions: actions,
            boardTask: .none,
            focus: .empty
        )
    }

}
