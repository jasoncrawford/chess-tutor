#if DEBUG
import SwiftUI

struct VisualCoachingUITestFixture: View {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-ui-test-visual-coaching") }
    @State private var session: GameSession
    @State private var provider: VisualFixtureProvider
    @Namespace private var captures

    init() {
        let provider = VisualFixtureProvider()
        _provider = State(initialValue: provider)
        let state: GameState = provider.scenario == "question" || provider.scenario == "explanation"
            ? GameState(board: Board(pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                Square(file: .b, rank: 8): Piece(kind: .rook, color: .black),
                Square(file: .b, rank: 1): Piece(kind: .knight, color: .white),
                Square(file: .g, rank: 1): Piece(kind: .knight, color: .white),
            ]), sideToMove: .white) : .startingPosition()
        let edgeState = GameState(board: Board(pieces: [
            Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
            Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            Square(file: .a, rank: 7): Piece(kind: .rook, color: .white),
            Square(file: .h, rank: 7): Piece(kind: .rook, color: .black)
        ]), sideToMove: .white)
        let session = GameSession(state: provider.scenario == "edge-drag" ? edgeState : state, hostedCoachingProvider: provider)
        if provider.scenario == "draft" {
            session.select(Square(file: .g, rank: 1))
            _ = session.moveSelectedPiece(to: Square(file: .h, rank: 3))
        }
        session.startCoaching()
        _session = State(initialValue: session)
    }

    var body: some View {
        GeometryReader { proxy in
            let arguments = ProcessInfo.processInfo.arguments
            let rotationIndex = arguments.firstIndex(of: "-visual-rotation")
            let rotation = rotationIndex.flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil } ?? 0
            let rotated = abs(rotation) == 90
            let wide = ProcessInfo.processInfo.arguments.contains("-visual-wide")
            let side = min(proxy.size.height - (wide ? 250 : 50), proxy.size.width - (wide ? 40 : 320))
            let layout = CoachingPanelLayout(tabletopRegionSize: CGSize(width: wide ? side : 280, height: wide ? 235 : side),
                physicalRegionSize: CGSize(width: rotated ? side : wide ? side : 280, height: rotated ? 280 : wide ? 235 : side),
                physicalAxis: wide || rotated ? .horizontal : .vertical)
            let axis = wide ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(spacing: 20))
            axis {
                ChessBoardView(session: session, captureNamespace: captures,
                               viewingAngle: rotation == 90 ? .clockwiseQuarterTurn : rotation == -90 ? .counterclockwiseQuarterTurn : .normal,
                               readableRotationDegrees: rotation, isCaptureTestModeEnabled: false)
                    .frame(width: side, height: side)
                SidebarPanelView(panelSize: layout.tabletopRegionSize) {
                    CoachingPanelView(session: session, presentation: session.coachingPresentation, layout: layout,
                                      readableRotationDegrees: rotation, onCommittedMove: { _ in })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.table)
        .overlay(alignment: .bottomTrailing) {
            VStack {
                Text("Requests: \(provider.calls)").accessibilityIdentifier("visual-request-count")
                Text("Focus: \(session.coachingPresentation?.focus.emphasizedSquares.map(ModelCoachingPositionEncoder.squareName).sorted().joined(separator: ",") ?? "")")
                    .accessibilityIdentifier("visual-focus")
            }.font(.caption).padding(4)
        }
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("-visual-large") ? .accessibility3 : .large)
        .task(id: session.coachingRequestIdentity) { await session.resolvePendingCoachingAdvice() }
    }
}

@Observable @MainActor private final class VisualFixtureProvider: HostedCoachingTurning {
    var calls = 0
    let scenario: String = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-ui-test-visual-coaching"), args.indices.contains(index + 1) else { return "question" }
        return args[index + 1]
    }()

    func turn(for request: ModelCoachingNeutralRequest, contract: ModelCoachingChessNativeResponseContract,
              continuationID: String?, correlation: HostedCoachingCorrelation) async throws -> HostedCoachingResponse {
        calls += 1
        let answerDelay = ProcessInfo.processInfo.arguments.contains("-visual-slow-answer") ? 15000 : 1800
        try await Task.sleep(for: .milliseconds(request.interaction.latestEvent.kind == .pieceSelected ? answerDelay : 150))
        let content: ModelCoachingVisualContent
        let expects: ModelCoachingChessNativeExpectedResponse
        if scenario == "edge-drag" {
            content = .init(runs: [.text("Tap the rook that needs help.")], visuals: [])
            expects = request.interaction.tentativeMove == nil ? .findEndangeredPiece : .chooseWhetherToPlay
        } else if scenario == "question" && request.interaction.tentativeMove != nil {
            content = .init(runs: [.text("Your knight moved out of the rook's path.")], visuals: [])
            expects = .chooseWhetherToPlay
        } else if scenario == "question" && request.interaction.latestEvent.kind != .pieceSelected {
            content = .init(runs: [.text("A rook attacks one of your knights. Tap the knight that needs help.")], visuals: [])
            expects = .findEndangeredPiece
        } else if scenario == "question" || scenario == "explanation" {
            content = .init(runs: [.piece(text: "This rook", square: "b8"), .text(" attacks "),
                .piece(text: "your knight", square: "b1"), .text(". Can you move it out of the way?")], visuals: [.attack(from: "b8", to: "b1")])
            expects = .stageMove
        } else if scenario == "paragraph" {
            // Layout-only sample matching the long linked phrases from play testing.
            content = .init(runs: [.text("That brings "), .piece(text: "your other knight", square: "g1"),
                .text(" off the back row and into the game. It now attacks "),
                .piece(text: "Black's middle pawn", square: "e7"), .text(".")], visuals: [])
            expects = .stageMove
        } else {
            content = .init(runs: [.text("Try moving "), .piece(text: "your knight", square: scenario == "draft" ? "h3" : "g1"),
                .text(" "), .square(text: "here", square: "f3"), .text(" to help control the middle.")], visuals: [.move(from: "g1", to: "f3")])
            expects = request.interaction.tentativeMove == nil ? .stageMove : .chooseWhetherToPlay
        }
        return .init(schemaVersion: "hosted-coaching-turn.v4", requestID: request.requestID,
            positionRevision: request.positionRevision, promptVersion: "tutor-v14", continuationID: "resp_fixture",
            turn: .init(message: content.plainText, actions: ["hint"], focus: [], expects: expects, visualContent: content),
            metrics: .init(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, reasoningTokens: 0, totalTokens: 0, latencyMilliseconds: 150))
    }
}
#endif
