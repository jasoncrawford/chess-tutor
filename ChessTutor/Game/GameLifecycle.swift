import Foundation

struct ManagedGameID: Codable, Equatable, Hashable, Sendable, Identifiable {
    let rawValue: UUID

    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct ManagedLocalGame: Codable, Equatable, Sendable, Identifiable {
    let id: ManagedGameID
    let createdAt: Date
    private(set) var lastMovedAt: Date
    private(set) var moves: [Move]

    init(id: ManagedGameID, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
        self.lastMovedAt = createdAt
        self.moves = []
    }

    mutating func record(_ move: Move, at date: Date) {
        moves.append(move)
        lastMovedAt = date
    }
}

enum GameLibraryRoute: Codable, Equatable, Sendable {
    case games
    case board(ManagedGameID)
}

struct GameLibrarySnapshot: Codable, Equatable, Sendable {
    let games: [ManagedLocalGame]
    let route: GameLibraryRoute
}

final class GameLibraryStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func load() throws -> GameLibrarySnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(GameLibrarySnapshot.self, from: Data(contentsOf: fileURL))
    }

    func save(_ snapshot: GameLibrarySnapshot) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent("Games", isDirectory: true).appendingPathComponent("library.json")
    }
}

@MainActor
final class GameLibrary {
    private let now: () -> Date
    private(set) var games: [ManagedLocalGame] = []
    private(set) var route: GameLibraryRoute = .games

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    @discardableResult
    func createLocalGame(at date: Date? = nil) -> ManagedLocalGame {
        let game = ManagedLocalGame(id: ManagedGameID(), createdAt: date ?? now())
        games.insert(game, at: 0)
        return game
    }

    func game(id: ManagedGameID) -> ManagedLocalGame? {
        games.first(where: { $0.id == id })
    }

    var snapshot: GameLibrarySnapshot {
        GameLibrarySnapshot(games: games, route: route)
    }

    func showBoard(_ id: ManagedGameID) {
        guard game(id: id) != nil else { return }
        route = .board(id)
    }

    func showGames() {
        route = .games
    }

    func recordCommittedMove(_ move: Move, in id: ManagedGameID, at date: Date? = nil) {
        guard let index = games.firstIndex(where: { $0.id == id }) else {
            return
        }
        games[index].record(move, at: date ?? now())
        let updated = games.remove(at: index)
        games.insert(updated, at: 0)
    }
}

@MainActor
enum GameLifecycle {
    static func startNewGame(
        session: GameSession,
        remotePlayFlow: RemotePlayFlow
    ) {
        remotePlayFlow.cancel()
        session.whitePlayer = .humanLocal
        session.blackPlayer = .humanLocal
        session.newGame()
    }

    #if DEBUG
    static func startNewGame(
        session: GameSession,
        remotePlayFlow: RemotePlayFlow,
        fakeRemoteLab: FakeRemoteGameLab?
    ) {
        fakeRemoteLab?.stop(session: session)
        startNewGame(session: session, remotePlayFlow: remotePlayFlow)
    }
    #endif
}
