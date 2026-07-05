protocol RemoteGameTransport {
    func sendMove(_ event: RemoteMoveEvent) async throws -> RemoteMoveAck
    func fetchMoves(gameID: RemoteGameID, after sequenceNumber: Int) async throws -> [RemoteMoveEvent]
}

actor InMemoryRemoteGameTransport: RemoteGameTransport {
    private var eventsByGame: [RemoteGameID: [RemoteMoveEvent]] = [:]

    func sendMove(_ event: RemoteMoveEvent) async throws -> RemoteMoveAck {
        var events = eventsByGame[event.gameID, default: []]
        if let existing = events.first(where: { $0.sequenceNumber == event.sequenceNumber }) {
            if existing == event {
                return RemoteMoveAck(
                    eventID: existing.id,
                    gameID: existing.gameID,
                    sequenceNumber: existing.sequenceNumber
                )
            }
            throw InMemoryRemoteGameTransportError.conflictingSequence(event.sequenceNumber)
        }

        events.append(event)
        events.sort { $0.sequenceNumber < $1.sequenceNumber }
        eventsByGame[event.gameID] = events
        return RemoteMoveAck(eventID: event.id, gameID: event.gameID, sequenceNumber: event.sequenceNumber)
    }

    func fetchMoves(gameID: RemoteGameID, after sequenceNumber: Int) async throws -> [RemoteMoveEvent] {
        eventsByGame[gameID, default: []]
            .filter { $0.sequenceNumber > sequenceNumber }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    #if DEBUG
    func storeForTesting(_ event: RemoteMoveEvent) {
        var events = eventsByGame[event.gameID, default: []]
        events.removeAll { $0.sequenceNumber == event.sequenceNumber }
        events.append(event)
        events.sort { $0.sequenceNumber < $1.sequenceNumber }
        eventsByGame[event.gameID] = events
    }
    #endif
}

enum InMemoryRemoteGameTransportError: Swift.Error, Equatable {
    case conflictingSequence(Int)
}
