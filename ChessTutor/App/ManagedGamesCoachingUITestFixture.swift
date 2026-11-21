#if DEBUG
import Security
import SwiftUI

/// Only this UUID-scoped Debug fixture may select or remove test credentials.
struct HostedConfigurationUITestSupport {
    let id: UUID

    static var current: Self? {
        let prefix = "-ui-test-hosted-config-"
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
              let id = UUID(uuidString: String(argument.dropFirst(prefix.count))) else { return nil }
        return Self(id: id)
    }

    var credentialStore: KeychainHostedCoachingCredentialStore {
        KeychainHostedCoachingCredentialStore(service: "org.jasoncrawford.chesstutor.ui-test.\(id.uuidString)")
    }

    var libraryURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hosted-config-test-\(id.uuidString).json")
    }

    func cleanup() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialStore.service,
            kSecAttrAccount as String: credentialStore.account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HostedCoachingConfigurationError.credentialStoreFailure
        }
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            try FileManager.default.removeItem(at: libraryURL)
        }
    }
}

struct HostedConfigurationUITestFixture: View {
    let support: HostedConfigurationUITestSupport
    let provider: (any HostedCoachingTurning)?
    @State private var cleanupMessage = "Cleaning up configuration test"

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-cleanup-hosted-config-test") {
            Text(cleanupMessage).task {
                do {
                    try support.cleanup()
                    cleanupMessage = "Configuration test cleanup complete"
                } catch {
                    cleanupMessage = "Configuration test cleanup failed"
                }
            }
        } else {
            ContentView(
                hostedCoachingProvider: provider,
                gameLibraryStore: GameLibraryStore(fileURL: support.libraryURL)
            )
        }
    }
}

/// Exercises the real root view and persistence with an isolated store and no paid API calls.
struct ManagedGamesCoachingUITestFixture: View {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-test-managed-games")
    }

    private let store: GameLibraryStore
    private let provider: ManagedGamesCoachingUITestProvider
    private let testsPieceAnswers: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        testsPieceAnswers = arguments.contains("-test-piece-answer-burst")
        let runID = arguments.first(where: { $0.hasPrefix("managed-games-run-") }) ?? UUID().uuidString
        store = GameLibraryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(runID).json"))
        provider = ManagedGamesCoachingUITestProvider(
            delayFirst: arguments.contains("-delay-first-help"), testsPieceAnswers: testsPieceAnswers
        )
    }

    var body: some View {
        ContentView(hostedCoachingProvider: provider, gameLibraryStore: store)
            .overlay(alignment: .bottomTrailing) {
                if testsPieceAnswers {
                    Button("Release test advice") {
                        Task { await provider.releaseAnswer() }
                    }
                    .padding(8)
                    .background(.white)
                }
            }
    }
}

private actor ManagedGamesCoachingUITestProvider: HostedCoachingTurning {
    private var delayFirst: Bool
    private let testsPieceAnswers: Bool
    private var holdsAnswer: Bool
    private var answerWaiter: CheckedContinuation<Void, Never>?

    init(delayFirst: Bool, testsPieceAnswers: Bool) {
        self.delayFirst = delayFirst
        self.testsPieceAnswers = testsPieceAnswers
        self.holdsAnswer = testsPieceAnswers
    }

    func releaseAnswer() {
        holdsAnswer = false
        answerWaiter?.resume()
        answerWaiter = nil
    }

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
        let isAnswer = request.interaction.latestEvent.kind == .pieceSelected
        if testsPieceAnswers && isAnswer && holdsAnswer {
            await withCheckedContinuation { answerWaiter = $0 }
        }
        let message = testsPieceAnswers
            ? (isAnswer ? "Selected \(request.interaction.latestEvent.referencedIDs.last ?? "none")." : "Choose a knight.")
            : "Game \(correlation.gameID). Moves: \(request.gameHistory.count)."
        return HostedCoachingResponse(
            schemaVersion: "hosted-coaching-turn.v3", requestID: request.requestID,
            positionRevision: request.positionRevision, promptVersion: "managed-games-ui-test",
            continuationID: "test-\(correlation.episodeID)",
            turn: ModelCoachingChessNativeTurn(
                message: message, actions: ["hint"], focus: [],
                expects: testsPieceAnswers && !isAnswer ? .selectPiece : .stageMove
            ),
            metrics: HostedCoachingMetrics(
                inputTokens: 0, cachedInputTokens: 0, outputTokens: 0,
                reasoningTokens: 0, totalTokens: 0, latencyMilliseconds: 0
            )
        )
    }
}
#endif
