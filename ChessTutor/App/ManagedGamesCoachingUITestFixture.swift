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

/// Opt-in, run-scoped evidence for #29. No recognizers or event handlers are replaced.
@MainActor
enum GameNavigationDiagnostics {
    static var isEnabled: Bool {
        ManagedGamesCoachingUITestFixture.isEnabled
            && ProcessInfo.processInfo.arguments.contains("-trace-game-navigation")
    }

    private static let fileURL: URL = {
        let runID = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("managed-games-run-") })
            ?? UUID().uuidString
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(runID)-navigation.jsonl")
    }()
    private static var sequence = 0

    static func record(_ name: String, fields: [String: String] = [:]) {
        guard isEnabled else { return }
        sequence += 1
        do {
            var data = try JSONSerialization.data(withJSONObject: [
                "event": "gameNavigation.\(name)", "sequence": sequence,
                "processID": ProcessInfo.processInfo.processIdentifier,
                "timestamp": Date().timeIntervalSince1970, "fields": fields,
            ], options: [.sortedKeys])
            data.append(0x0A)
            // Complete the small append before returning: a failure attachment
            // may terminate this process immediately after the final event.
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL)
            } else {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
        } catch {
            NSLog("Game navigation trace write failed: %@", String(describing: error))
        }
    }

    static func exportText() -> String {
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return "Could not read navigation trace: \(error)"
        }
    }

    static func routeName(_ route: GameLibraryRoute) -> String {
        switch route {
        case .games: "games"
        case .board(let id): "board:\(id.rawValue.uuidString)"
        }
    }
}

/// Records UIKit's hit-test arrival, then always declines the hit without
/// adding a recognizer or changing gesture arbitration.
struct GameNavigationTouchProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ uiView: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            if bounds.contains(point), event?.type == .touches {
                let windowPoint = convert(point, to: nil)
                GameNavigationDiagnostics.record("hitTest", fields: [
                    "x": String(format: "%.1f", windowPoint.x),
                    "y": String(format: "%.1f", windowPoint.y),
                    "eventTime": String(event?.timestamp ?? 0),
                ])
            }
            return nil
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
    @State private var navigationTrace: String?

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
        if GameNavigationDiagnostics.isEnabled,
           ProcessInfo.processInfo.arguments.contains("-dump-game-navigation") {
            ScrollView {
                if let navigationTrace {
                    Text(navigationTrace)
                        .accessibilityIdentifier("game-navigation-trace")
                }
            }
            .task { navigationTrace = GameNavigationDiagnostics.exportText() }
        } else {
            playSurface
        }
    }

    private var playSurface: some View {
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
