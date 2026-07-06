import Foundation

struct LocalRemotePlayerProfile: Codable, Equatable, Sendable {
    let id: RemotePlayerID
    var displayName: String
}

final class RemoteIdentityStore {
    private struct StoredState: Codable {
        var localProfile: LocalRemotePlayerProfile?
        var knownPlayers: [KnownRemotePlayer]
    }

    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func loadLocalProfile() throws -> LocalRemotePlayerProfile {
        var state = try loadState()
        if let localProfile = state.localProfile {
            return localProfile
        }

        let localProfile = LocalRemotePlayerProfile(
            id: RemotePlayerID(rawValue: UUID().uuidString),
            displayName: "Me"
        )
        state.localProfile = localProfile
        try saveState(state)
        return localProfile
    }

    func loadKnownPlayers() throws -> [KnownRemotePlayer] {
        try loadState().knownPlayers
    }

    func saveKnownPlayer(_ player: KnownRemotePlayer) throws {
        var state = try loadState()
        if let existingIndex = state.knownPlayers.firstIndex(where: { $0.id == player.id }) {
            state.knownPlayers[existingIndex] = player
        } else {
            state.knownPlayers.append(player)
        }
        state.knownPlayers.sort {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        try saveState(state)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return directory
            .appendingPathComponent("RemoteIdentity", isDirectory: true)
            .appendingPathComponent("identity.json")
    }

    private func loadState() throws -> StoredState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return StoredState(localProfile: nil, knownPlayers: [])
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(StoredState.self, from: data)
    }

    private func saveState(_ state: StoredState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
