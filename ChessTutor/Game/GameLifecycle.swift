import Foundation
import Observation

enum GameActivityDateFormatter {
    static func string(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0

        let dayLabel: String
        switch daysAgo {
        case 0:
            dayLabel = "Today"
        case 1:
            dayLabel = "Yesterday"
        case 2...6:
            dayLabel = date.formatted(.dateTime.weekday(.wide))
        default:
            let isCurrentYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            dayLabel = date.formatted(
                isCurrentYear
                    ? .dateTime.month(.abbreviated).day()
                    : .dateTime.month(.abbreviated).day().year()
            )
        }

        return "\(dayLabel), \(date.formatted(date: .omitted, time: .shortened))"
    }
}

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

/// A remote invitation has a board before it can be played.  Keeping that
/// lightweight record in the library lets the UI treat it like every other
/// game without pretending it is an active remote match yet.
struct ManagedPendingRemoteBoard: Codable, Equatable, Sendable, Identifiable {
    enum ReopenedInvitationPresentation: Equatable, Sendable {
        case showInviteDetails
        case confirmInvitation
    }

    enum Role: String, Codable, Equatable, Sendable {
        case inviter
        case invitee
    }

    let id: ManagedGameID
    let invite: RemotePendingInvite
    let role: Role
    let createdAt: Date
    private(set) var lastUpdatedAt: Date

    init(id: ManagedGameID, invite: RemotePendingInvite, role: Role, createdAt: Date) {
        self.id = id
        self.invite = invite
        self.role = role
        self.createdAt = createdAt
        self.lastUpdatedAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, invite, role, createdAt, lastUpdatedAt }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ManagedGameID.self, forKey: .id)
        invite = try container.decode(RemotePendingInvite.self, forKey: .invite)
        role = try container.decodeIfPresent(Role.self, forKey: .role) ?? .invitee
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUpdatedAt = try container.decode(Date.self, forKey: .lastUpdatedAt)
    }

    var listTitle: String {
        role == .inviter ? (invite.inviteeDisplayName ?? "New player") : invite.inviter.displayName
    }

    var listStatus: String {
        role == .inviter ? "Invitation sent" : "Invitation pending"
    }

    var inviteLink: URL {
        var components = URLComponents()
        components.scheme = "chesstutor"
        components.host = "invite"
        components.queryItems = [
            URLQueryItem(name: "code", value: invite.code.rawValue),
            URLQueryItem(name: "token", value: invite.token.rawValue),
        ]
        return components.url!
    }

    var reopenedInvitationPresentation: ReopenedInvitationPresentation {
        role == .inviter ? .showInviteDetails : .confirmInvitation
    }
}

struct ManagedRemoteGame: Codable, Equatable, Sendable, Identifiable {
    let id: ManagedGameID
    let createdAt: Date
    private(set) var lastMovedAt: Date
    private(set) var snapshot: ActiveRemoteGameSnapshot

    init(id: ManagedGameID, createdAt: Date, snapshot: ActiveRemoteGameSnapshot) {
        self.id = id
        self.createdAt = createdAt
        self.lastMovedAt = createdAt
        self.snapshot = snapshot
    }

    mutating func update(snapshot: ActiveRemoteGameSnapshot, at date: Date) {
        self.snapshot = snapshot
        lastMovedAt = date
    }
}

enum GameLibraryRoute: Codable, Equatable, Sendable {
    case games
    case board(ManagedGameID)
}

enum GameLibraryEntry: Identifiable, Sendable {
    case local(ManagedLocalGame)
    case pendingRemote(ManagedPendingRemoteBoard)
    case remote(ManagedRemoteGame)

    var id: ManagedGameID {
        switch self {
        case .local(let game): game.id
        case .pendingRemote(let board): board.id
        case .remote(let game): game.id
        }
    }

    var lastActivityAt: Date {
        switch self {
        case .local(let game): game.lastMovedAt
        case .pendingRemote(let board): board.lastUpdatedAt
        case .remote(let game): game.lastMovedAt
        }
    }

    var cardPresentation: GameCardPresentation {
        switch self {
        case .local(let game):
            let boardState = GameCardPresentation.boardState(replaying: game.moves)
            return GameCardPresentation(
                title: "Local game",
                status: GameCardPresentation.status(for: boardState),
                statusIndicator: GameCardPresentation.indicator(for: boardState),
                moves: game.moves,
                lastActivityAt: game.lastMovedAt
            )
        case .pendingRemote(let board):
            return GameCardPresentation(
                title: board.listTitle,
                status: board.listStatus,
                statusIndicator: .waiting,
                moves: [],
                lastActivityAt: board.lastUpdatedAt
            )
        case .remote(let game):
            let descriptor = game.snapshot.descriptor
            let opponent = descriptor.localPlayerID == descriptor.whitePlayer.id
                ? descriptor.blackPlayer
                : descriptor.whitePlayer
            let moves = game.snapshot.acceptedEvents.compactMap { try? RemoteMoveCodec.decode($0.move) }
            let boardState = GameCardPresentation.boardState(replaying: moves)
            let localColor: PieceColor = descriptor.localPlayerID == descriptor.whitePlayer.id ? .white : .black
            return GameCardPresentation(
                title: opponent.displayName,
                status: descriptor.status == .ended
                    ? "Finished"
                    : (boardState.sideToMove == localColor ? "Your turn" : "Their turn"),
                statusIndicator: descriptor.status == .ended
                    ? .finished
                    : (boardState.sideToMove == localColor ? .yourTurn : .waiting),
                moves: moves,
                lastActivityAt: game.lastMovedAt
            )
        }
    }
}

struct GameCardPresentation: Equatable, Sendable {
    enum StatusIndicator: Equatable, Sendable {
        case neutral
        case yourTurn
        case waiting
        case finished
    }

    let title: String
    let status: String
    let statusIndicator: StatusIndicator
    let moves: [Move]
    let lastActivityAt: Date
    let boardState: GameState

    init(
        title: String,
        status: String,
        statusIndicator: StatusIndicator,
        moves: [Move],
        lastActivityAt: Date
    ) {
        self.title = title
        self.status = status
        self.statusIndicator = statusIndicator
        self.moves = moves
        self.lastActivityAt = lastActivityAt
        self.boardState = Self.boardState(replaying: moves)
    }

    static func boardState(replaying moves: [Move]) -> GameState {
        moves.reduce(into: .startingPosition()) { state, move in
            state.apply(move)
        }
    }

    static func status(for state: GameState) -> String {
        switch state.result {
        case .ongoing:
            return "\(state.sideToMove.rawValue.capitalized)’s turn"
        case .checkmate(let winner):
            return "Checkmate. \(winner.rawValue.capitalized) wins."
        case .stalemate:
            return "Stalemate."
        }
    }

    static func indicator(for state: GameState) -> StatusIndicator {
        state.result == .ongoing ? .neutral : .finished
    }
}

struct GameLibrarySnapshot: Codable, Equatable, Sendable {
    let games: [ManagedLocalGame]
    let pendingRemoteBoards: [ManagedPendingRemoteBoard]
    let remoteGames: [ManagedRemoteGame]
    let route: GameLibraryRoute

    init(
        games: [ManagedLocalGame],
        pendingRemoteBoards: [ManagedPendingRemoteBoard] = [],
        remoteGames: [ManagedRemoteGame] = [],
        route: GameLibraryRoute
    ) {
        self.games = games
        self.pendingRemoteBoards = pendingRemoteBoards
        self.remoteGames = remoteGames
        self.route = route
    }

    private enum CodingKeys: String, CodingKey {
        case games
        case pendingRemoteBoards
        case remoteGames
        case route
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        games = try container.decode([ManagedLocalGame].self, forKey: .games)
        pendingRemoteBoards = try container.decodeIfPresent([ManagedPendingRemoteBoard].self, forKey: .pendingRemoteBoards) ?? []
        remoteGames = try container.decodeIfPresent([ManagedRemoteGame].self, forKey: .remoteGames) ?? []
        route = try container.decode(GameLibraryRoute.self, forKey: .route)
    }
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
@Observable
final class GameLibrary {
    private let now: () -> Date
    private(set) var games: [ManagedLocalGame] = []
    private(set) var pendingRemoteBoards: [ManagedPendingRemoteBoard] = []
    private(set) var remoteGames: [ManagedRemoteGame] = []
    private(set) var route: GameLibraryRoute = .games

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    init(snapshot: GameLibrarySnapshot, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.games = snapshot.games
        self.pendingRemoteBoards = snapshot.pendingRemoteBoards
        self.remoteGames = snapshot.remoteGames
        self.route = snapshot.route
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

    func pendingRemoteBoard(id: ManagedGameID) -> ManagedPendingRemoteBoard? {
        pendingRemoteBoards.first(where: { $0.id == id })
    }

    func pendingRemoteBoard(inviteID: RemoteInviteID) -> ManagedPendingRemoteBoard? {
        pendingRemoteBoards.first(where: { $0.invite.id == inviteID })
    }

    func remoteGame(id: ManagedGameID) -> ManagedRemoteGame? {
        remoteGames.first(where: { $0.id == id })
    }

    func remoteGame(inviteID: RemoteInviteID) -> ManagedRemoteGame? {
        remoteGames.first(where: { $0.snapshot.descriptor.id.rawValue == inviteID.rawValue })
    }

    @discardableResult
    func createPendingRemoteBoard(
        _ invite: RemotePendingInvite,
        role: ManagedPendingRemoteBoard.Role = .invitee,
        at date: Date? = nil
    ) -> ManagedPendingRemoteBoard {
        if let existing = pendingRemoteBoard(inviteID: invite.id) {
            return existing
        }
        let board = ManagedPendingRemoteBoard(id: ManagedGameID(), invite: invite, role: role, createdAt: date ?? now())
        pendingRemoteBoards.insert(board, at: 0)
        return board
    }

    @discardableResult
    func activateRemoteBoard(
        for inviteID: RemoteInviteID,
        snapshot: ActiveRemoteGameSnapshot,
        at date: Date? = nil
    ) -> ManagedRemoteGame {
        let timestamp = date ?? now()
        let id = pendingRemoteBoard(inviteID: inviteID)?.id ?? ManagedGameID()
        pendingRemoteBoards.removeAll(where: { $0.id == id })
        let game = ManagedRemoteGame(id: id, createdAt: timestamp, snapshot: snapshot)
        remoteGames.removeAll(where: { $0.id == id })
        remoteGames.insert(game, at: 0)
        return game
    }

    func updateRemoteGame(_ snapshot: ActiveRemoteGameSnapshot, in id: ManagedGameID, at date: Date? = nil) {
        guard let index = remoteGames.firstIndex(where: { $0.id == id }) else { return }
        remoteGames[index].update(snapshot: snapshot, at: date ?? now())
        let updated = remoteGames.remove(at: index)
        remoteGames.insert(updated, at: 0)
    }

    func removePendingRemoteBoard(inviteID: RemoteInviteID) {
        pendingRemoteBoards.removeAll(where: { $0.invite.id == inviteID })
        if case let .board(id) = route,
           pendingRemoteBoard(id: id) == nil {
            route = .games
        }
    }

    var snapshot: GameLibrarySnapshot {
        GameLibrarySnapshot(games: games, pendingRemoteBoards: pendingRemoteBoards, remoteGames: remoteGames, route: route)
    }

    var entries: [GameLibraryEntry] {
        (games.map(GameLibraryEntry.local)
            + pendingRemoteBoards.map(GameLibraryEntry.pendingRemote)
            + remoteGames.map(GameLibraryEntry.remote))
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    func showBoard(_ id: ManagedGameID) {
        guard game(id: id) != nil || pendingRemoteBoard(id: id) != nil || remoteGame(id: id) != nil else { return }
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
