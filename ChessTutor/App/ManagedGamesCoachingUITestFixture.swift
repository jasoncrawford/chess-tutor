#if DEBUG
import SwiftUI

/// Exercises the real root view and persistence with an isolated store and no paid API calls.
struct ManagedGamesCoachingUITestFixture: View {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-test-managed-games")
    }

    private let store: GameLibraryStore
    private let provider: ManagedGamesCoachingUITestProvider

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let runID = arguments.first(where: { $0.hasPrefix("managed-games-run-") }) ?? UUID().uuidString
        store = GameLibraryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(runID).json"))
        provider = ManagedGamesCoachingUITestProvider(delayFirst: arguments.contains("-delay-first-help"))
    }

    var body: some View {
        ContentView(hostedCoachingProvider: provider, gameLibraryStore: store)
    }
}

private actor ManagedGamesCoachingUITestProvider: HostedCoachingTurning {
    private var delayFirst: Bool

    init(delayFirst: Bool) { self.delayFirst = delayFirst }

    func turn(
        for request: ModelCoachingNeutralRequest,
        contract: ModelCoachingChessNativeResponseContract,
        continuationID: String?,
        correlation: HostedCoachingCorrelation
    ) async throws -> HostedCoachingResponse {
        if delayFirst {
            delayFirst = false
            try await Task.sleep(for: .seconds(10))
        }
        return HostedCoachingResponse(
            schemaVersion: "hosted-coaching-turn.v3", requestID: request.requestID,
            positionRevision: request.positionRevision, promptVersion: "managed-games-ui-test",
            continuationID: "test-\(correlation.episodeID)",
            turn: ModelCoachingChessNativeTurn(
                message: "Game \(correlation.gameID). Moves: \(request.gameHistory.count).",
                actions: ["hint"], focus: [], expects: .stageMove
            ),
            metrics: HostedCoachingMetrics(
                inputTokens: 0, cachedInputTokens: 0, outputTokens: 0,
                reasoningTokens: 0, totalTokens: 0, latencyMilliseconds: 0
            )
        )
    }
}
#endif
