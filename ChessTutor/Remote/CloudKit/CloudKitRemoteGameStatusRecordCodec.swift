import CloudKit
import Foundation

enum CloudKitRemoteGameStatusRecordCodec {
    enum Error: Swift.Error, Equatable {
        case missingField(String)
        case invalidStatus(String)
    }

    static let recordType = "RemoteGameStatus"

    enum Field {
        static let gameID = "gameID"
        static let status = "status"
        static let updatedByPlayerID = "updatedByPlayerID"
        static let updatedByDisplayName = "updatedByDisplayName"
        static let updatedAt = "updatedAt"
    }

    static func recordID(gameID: RemoteGameID) -> CKRecord.ID {
        CKRecord.ID(recordName: "game-status-\(gameID.rawValue)")
    }

    static func record(from status: RemoteGameStatusUpdate) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID(gameID: status.gameID))
        apply(status, to: record)
        return record
    }

    static func apply(_ status: RemoteGameStatusUpdate, to record: CKRecord) {
        record[Field.gameID] = status.gameID.rawValue as CKRecordValue
        record[Field.status] = status.status.rawValue as CKRecordValue
        record[Field.updatedByPlayerID] = status.updatedByPlayerID.rawValue as CKRecordValue
        record[Field.updatedByDisplayName] = status.updatedByDisplayName as CKRecordValue?
        record[Field.updatedAt] = status.updatedAt as CKRecordValue
    }

    static func status(from record: CKRecord) throws -> RemoteGameStatusUpdate {
        let rawStatus = try string(Field.status, from: record)
        guard let status = RemoteGameStatus(rawValue: rawStatus) else {
            throw Error.invalidStatus(rawStatus)
        }

        return RemoteGameStatusUpdate(
            gameID: RemoteGameID(rawValue: try string(Field.gameID, from: record)),
            status: status,
            updatedByPlayerID: RemotePlayerID(rawValue: try string(Field.updatedByPlayerID, from: record)),
            updatedByDisplayName: record[Field.updatedByDisplayName] as? String,
            updatedAt: try date(Field.updatedAt, from: record)
        )
    }

    private static func string(_ key: String, from record: CKRecord) throws -> String {
        guard let value = record[key] as? String else {
            throw Error.missingField(key)
        }
        return value
    }

    private static func date(_ key: String, from record: CKRecord) throws -> Date {
        guard let value = record[key] as? Date else {
            throw Error.missingField(key)
        }
        return value
    }
}
