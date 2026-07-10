import CloudKit
import Foundation

enum CloudKitRemotePresenceRecordCodec {
    enum Error: Swift.Error, Equatable {
        case missingField(String)
        case invalidPresenceState(String)
    }

    static let recordType = "RemotePresence"

    enum Field {
        static let gameID = "gameID"
        static let playerID = "playerID"
        static let state = "state"
        static let updatedAt = "updatedAt"
        static let expiresAt = "expiresAt"
    }

    static func recordID(gameID: RemoteGameID, playerID: RemotePlayerID) -> CKRecord.ID {
        CKRecord.ID(recordName: "presence-\(gameID.rawValue)-\(playerID.rawValue)")
    }

    static func record(from presence: RemotePresenceUpdate) -> CKRecord {
        let record = CKRecord(
            recordType: recordType,
            recordID: recordID(gameID: presence.gameID, playerID: presence.playerID)
        )
        record[Field.gameID] = presence.gameID.rawValue as CKRecordValue
        record[Field.playerID] = presence.playerID.rawValue as CKRecordValue
        record[Field.state] = presence.state.rawValue as CKRecordValue
        record[Field.updatedAt] = presence.updatedAt as CKRecordValue
        record[Field.expiresAt] = presence.expiresAt as CKRecordValue
        return record
    }

    static func presence(from record: CKRecord) throws -> RemotePresenceUpdate {
        RemotePresenceUpdate(
            gameID: RemoteGameID(rawValue: try string(Field.gameID, from: record)),
            playerID: RemotePlayerID(rawValue: try string(Field.playerID, from: record)),
            state: try presenceState(from: record),
            updatedAt: try date(Field.updatedAt, from: record),
            expiresAt: try date(Field.expiresAt, from: record)
        )
    }

    private static func presenceState(from record: CKRecord) throws -> RemotePresenceState {
        let rawValue = try string(Field.state, from: record)
        guard let state = RemotePresenceState(rawValue: rawValue) else {
            throw Error.invalidPresenceState(rawValue)
        }
        return state
    }

    private static func string(_ field: CKRecord.FieldKey, from record: CKRecord) throws -> String {
        guard let value = record[field] as? String else {
            throw Error.missingField(field)
        }
        return value
    }

    private static func date(_ field: CKRecord.FieldKey, from record: CKRecord) throws -> Date {
        guard let value = record[field] as? Date else {
            throw Error.missingField(field)
        }
        return value
    }
}
