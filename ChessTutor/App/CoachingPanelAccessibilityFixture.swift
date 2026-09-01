#if DEBUG
import SwiftUI

enum CoachingPanelAccessibilityFixtureConfiguration {
    case tall(CoachingPanelAccessibilityFixtureTurn)
    case clockwiseQuarterTurn(CoachingPanelAccessibilityFixtureTurn)
    case counterclockwiseQuarterTurn(CoachingPanelAccessibilityFixtureTurn)

    var composition: CoachingPanelComposition {
        switch self {
        case .tall:
            return .tall
        case .clockwiseQuarterTurn, .counterclockwiseQuarterTurn:
            return .wide
        }
    }

    var tableRotationDegrees: Double {
        switch self {
        case .tall:
            return 0
        case .clockwiseQuarterTurn:
            return 90
        case .counterclockwiseQuarterTurn:
            return -90
        }
    }

    var readableRotationDegrees: Double {
        -tableRotationDegrees
    }

    var turn: CoachingPanelAccessibilityFixtureTurn {
        switch self {
        case let .tall(turn),
             let .clockwiseQuarterTurn(turn),
             let .counterclockwiseQuarterTurn(turn):
            return turn
        }
    }
}

enum CoachingPanelAccessibilityFixtureTurn: String, CaseIterable {
    case compactNoObservation = "compact-no-observation"
    case compactWithObservation = "compact-with-observation"
}

struct CoachingPanelAccessibilityFixture: View {
    let configuration: CoachingPanelAccessibilityFixtureConfiguration

    @State private var session = GameSession()

    static var launchConfiguration: CoachingPanelAccessibilityFixtureConfiguration? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-ui-test-coaching-panel"),
              arguments.indices.contains(flagIndex + 2),
              let turn = CoachingPanelAccessibilityFixtureTurn(
                rawValue: arguments[flagIndex + 2]
              ) else {
            return nil
        }

        switch arguments[flagIndex + 1] {
        case "tall":
            return .tall(turn)
        case "clockwise-quarter-turn":
            return .clockwiseQuarterTurn(turn)
        case "counterclockwise-quarter-turn":
            return .counterclockwiseQuarterTurn(turn)
        default:
            return nil
        }
    }

    @ViewBuilder
    var body: some View {
        if let fixtureDynamicTypeSize {
            fixtureBody.environment(\.dynamicTypeSize, fixtureDynamicTypeSize)
        } else {
            fixtureBody
        }
    }

    private var fixtureBody: some View {
        ZStack {
            AppTheme.table.ignoresSafeArea()

            SidebarPanelView(panelSize: layout.tabletopRegionSize) {
                CoachingPanelView(
                    session: session,
                    presentation: presentation,
                    layout: layout,
                    readableRotationDegrees: configuration.readableRotationDegrees,
                    onCommittedMove: { _ in }
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coaching-panel-frame")
            .rotationEffect(.degrees(configuration.tableRotationDegrees))
            .frame(
                width: layout.physicalRegionSize.width,
                height: layout.physicalRegionSize.height
            )
        }
    }

    private var fixtureDynamicTypeSize: DynamicTypeSize? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-ui-test-dynamic-type-size"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        return arguments[flagIndex + 1] == "accessibility-extra-large"
            ? .accessibility3
            : .large
    }

    private var layout: CoachingPanelLayout {
        switch configuration.composition {
        case .tall:
            CoachingPanelLayout(
                tabletopRegionSize: CGSize(width: 260, height: 446),
                physicalRegionSize: CGSize(width: 260, height: 446),
                physicalAxis: .vertical
            )
        case .wide:
            CoachingPanelLayout(
                tabletopRegionSize: CGSize(width: 246.67, height: 503.34),
                physicalRegionSize: CGSize(width: 503.34, height: 246.67),
                physicalAxis: .horizontal
            )
        }
    }

    private var presentation: CoachingPresentation {
        switch configuration.turn {
        case .compactNoObservation:
            return CoachingPresentation(
                primaryMessage: "That move seems safe.",
                instruction: "Play it, or try another move.",
                observation: nil,
                hint: nil,
                routine: [.safeCurrent, .takePending, .wakePending],
                actions: [
                    CoachingActionPresentation(
                        action: .done,
                        title: "Play this move",
                        accessibilityLabel: "Play this move",
                        prominence: .primary
                    ),
                    CoachingActionPresentation(
                        action: .keepLooking,
                        title: "Try another move",
                        accessibilityLabel: "Try another move",
                        prominence: .secondary
                    ),
                    stopAction,
                ],
                boardTask: .none,
                focus: .empty
            )
        case .compactWithObservation:
            return CoachingPresentation(
                primaryMessage: "What could White do next?",
                instruction: "Tap a white piece that could check your king or win one of your pieces.",
                observation: "That bishop attacks your pawn, but the pawn is protected.",
                hint: nil,
                routine: [.safeCurrent, .takePending, .wakePending],
                actions: [
                    CoachingActionPresentation(
                        action: .looksSafe,
                        title: "Looks safe",
                        accessibilityLabel: "Looks safe",
                        prominence: .primary
                    ),
                    CoachingActionPresentation(
                        action: .hint,
                        title: "Hint",
                        accessibilityLabel: "Show a hint",
                        prominence: .primary
                    ),
                    stopAction,
                ],
                boardTask: .identify(allowsMoveRevision: true),
                focus: .empty
            )
        }
    }

    private var stopAction: CoachingActionPresentation {
        CoachingActionPresentation(
            action: .stop,
            title: "Close help",
            accessibilityLabel: "Close coaching help",
            prominence: .quiet
        )
    }
}

private struct DelayedLocalCoachingAdvisor: CoachingAdvising {
    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        try await Task.sleep(for: .seconds(4))
        return try await LocalCoachingAdvisor().advice(for: request)
    }
}

struct CoachingContinuityUITestFixture: View {
    @State private var session = GameSession(
        coachingAdvisor: DelayedLocalCoachingAdvisor()
    )
    @Namespace private var captureNamespace

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-test-coaching-continuity")
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppTheme.table.ignoresSafeArea()
            SidePanelView(
                session: session,
                viewingAngle: .normal,
                readableRotationDegrees: 0,
                captureNamespace: captureNamespace,
                sideLength: 720,
                remotePlayFlow: nil,
                onAbout: {},
                onPlayRemotely: {},
                onNewGame: {},
                remoteNewGameOpponentName: nil,
                remotePresence: nil,
                onInviteRemoteNewGame: {},
                onCommittedMove: { _ in },
                fakeRemoteLab: nil
            )
            .frame(
                width: PlaySurfaceLayout.sidePanelWidth,
                height: 720,
                alignment: .top
            )

            VStack {
                Button("Start coaching for continuity test") {
                    session.startCoaching()
                }

                Button("Stage knight move for continuity test") {
                    let move = Move(
                        from: Square(file: .g, rank: 1),
                        to: Square(file: .f, rank: 3)
                    )
                    session.select(move.from)
                    _ = session.moveSelectedPiece(to: move.to)
                }
            }
            .padding()
        }
        .task(id: session.pendingCoachingRequestID) {
            await session.resolvePendingCoachingAdvice()
        }
    }
}

private struct DelayedHostedCoachingProvider: HostedCoachingTurning {
    func turn(
        for request: ModelCoachingNeutralRequest,
        contract: ModelCoachingChessNativeResponseContract,
        continuationID: String?
    ) async throws -> HostedCoachingResponse {
        try await Task.sleep(for: .milliseconds(850))
        let turn: ModelCoachingChessNativeTurn
        switch request.interaction.latestEvent.kind {
        case .moveStaged:
            turn = ModelCoachingChessNativeTurn(
                message: "How does your knight help from f3?",
                actions: [],
                focus: [.move(from: "g1", to: "f3")],
                expects: .chooseWhetherToPlay
            )
        case .pieceSelected:
            turn = ModelCoachingChessNativeTurn(
                message: "Yes, that is the pawn to notice.",
                actions: [],
                focus: [.square("f2")]
            )
        case .actionChosen:
            turn = ModelCoachingChessNativeTurn(
                message: "Good check. Nothing needs help right now.",
                actions: [],
                focus: []
            )
        default:
            turn = ModelCoachingChessNativeTurn(
                message: "Can you find the pawn in danger?",
                actions: [],
                focus: [.square("f2")],
                expects: .findEndangeredPiece
            )
        }
        return HostedCoachingResponse(
            schemaVersion: "hosted-coaching-turn.v3",
            requestID: request.requestID,
            positionRevision: request.positionRevision,
            promptVersion: "tutor-v11",
            continuationID: "resp_ui-fixture",
            turn: turn,
            metrics: HostedCoachingMetrics(
                inputTokens: 100,
                cachedInputTokens: 0,
                outputTokens: 20,
                reasoningTokens: 5,
                totalTokens: 120,
                latencyMilliseconds: 4_000
            )
        )
    }
}

struct HostedCoachingContinuityUITestFixture: View {
    @State private var session = GameSession(
        hostedCoachingProvider: DelayedHostedCoachingProvider()
    )
    @Namespace private var captureNamespace

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-test-hosted-coaching-continuity")
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppTheme.table.ignoresSafeArea()
            SidePanelView(
                session: session,
                viewingAngle: .normal,
                readableRotationDegrees: 0,
                captureNamespace: captureNamespace,
                sideLength: 720,
                remotePlayFlow: nil,
                onAbout: {},
                onPlayRemotely: {},
                onNewGame: {},
                remoteNewGameOpponentName: nil,
                remotePresence: nil,
                onInviteRemoteNewGame: {},
                onCommittedMove: { _ in },
                fakeRemoteLab: nil
            )
            .frame(
                width: PlaySurfaceLayout.sidePanelWidth,
                height: 720,
                alignment: .top
            )

            VStack {
                Button("Start hosted coaching continuity test") {
                    session.startCoaching()
                }

                Button("Stage hosted knight move for continuity test") {
                    let move = Move(
                        from: Square(file: .g, rank: 1),
                        to: Square(file: .f, rank: 3)
                    )
                    session.select(move.from)
                    _ = session.moveSelectedPiece(to: move.to)
                }

                Button("Tap hosted pawn answer") {
                    _ = session.handleCoachingSquareTap(
                        Square(file: .f, rank: 2)
                    )
                }
            }
            .padding()
        }
        .task(id: session.pendingCoachingRequestID) {
            await session.resolvePendingCoachingAdvice()
        }
    }
}
#endif
