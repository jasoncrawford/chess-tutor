struct RemoteOutboxItem: Equatable, Sendable {
    enum State: String, Codable, Equatable, Sendable {
        case pendingUpload
        case uploading
        case uploaded
        case failedRetrying
        case offlineQueued
    }

    let event: RemoteMoveEvent
    var state: State
}

struct RemoteOutbox: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        case missingEvent(RemoteMoveEventID)
        case mismatchedAck
    }

    private(set) var items: [RemoteOutboxItem]

    init(events: [RemoteMoveEvent] = []) {
        self.items = events.map { RemoteOutboxItem(event: $0, state: .pendingUpload) }
    }

    mutating func append(_ event: RemoteMoveEvent) {
        items.append(RemoteOutboxItem(event: event, state: .pendingUpload))
    }

    mutating func markUploading(_ eventID: RemoteMoveEventID) throws {
        try update(eventID) { item in
            item.state = .uploading
        }
    }

    mutating func markUploaded(_ ack: RemoteMoveAck) throws {
        try update(ack.eventID) { item in
            guard item.event.gameID == ack.gameID,
                  item.event.sequenceNumber == ack.sequenceNumber else {
                throw Error.mismatchedAck
            }
            item.state = .uploaded
        }
    }

    var pendingEvents: [RemoteMoveEvent] {
        items.compactMap { item in
            switch item.state {
            case .pendingUpload, .failedRetrying, .offlineQueued:
                return item.event
            case .uploading, .uploaded:
                return nil
            }
        }
    }

    private mutating func update(
        _ eventID: RemoteMoveEventID,
        mutate: (inout RemoteOutboxItem) throws -> Void
    ) throws {
        guard let index = items.firstIndex(where: { $0.event.id == eventID }) else {
            throw Error.missingEvent(eventID)
        }
        try mutate(&items[index])
    }
}
