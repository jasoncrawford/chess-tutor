import Foundation

struct LocalRemotePlayerProfile: Codable, Equatable, Sendable {
    let id: RemotePlayerID
    var displayName: String?
}

final class RemoteIdentityStore {
    enum Error: Swift.Error, Equatable {
        case emptyDisplayName
    }

    private struct StoredState: Codable {
        var localProfile: LocalRemotePlayerProfile?
        var hasSavedLocalDisplayName: Bool?
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
        if var localProfile = state.localProfile {
            if localProfile.displayName == "Me", state.hasSavedLocalDisplayName != true {
                localProfile.displayName = nil
                state.localProfile = localProfile
                state.hasSavedLocalDisplayName = false
                try saveState(state)
            }
            return localProfile
        }

        let localProfile = LocalRemotePlayerProfile(
            id: RemotePlayerID(rawValue: UUID().uuidString),
            displayName: nil
        )
        state.localProfile = localProfile
        try saveState(state)
        return localProfile
    }

    func saveLocalDisplayName(_ displayName: String) throws -> LocalRemotePlayerProfile {
        guard let trimmedDisplayName = Self.trimmedNonEmptyName(displayName) else {
            throw Error.emptyDisplayName
        }

        var state = try loadState()
        let currentProfile = try loadLocalProfile()
        let updatedProfile = LocalRemotePlayerProfile(
            id: currentProfile.id,
            displayName: trimmedDisplayName
        )
        state.localProfile = updatedProfile
        state.hasSavedLocalDisplayName = true
        try saveState(state)
        return updatedProfile
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

    private static func trimmedNonEmptyName(_ displayName: String) -> String? {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private func loadState() throws -> StoredState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return StoredState(localProfile: nil, hasSavedLocalDisplayName: nil, knownPlayers: [])
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
