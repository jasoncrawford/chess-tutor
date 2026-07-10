import CloudKit
import Foundation

enum CloudKitRemoteMoveRecordCodec {
    enum Error: Swift.Error, Equatable {
        case missingField(String)
        case invalidSpecial(String)
        case invalidPromotionPiece(String)
    }

    static let recordType = "RemoteMoveEvent"

    enum Field {
        static let eventID = "eventID"
        static let gameID = "gameID"
        static let sequenceNumber = "sequenceNumber"
        static let actorPlayerID = "actorPlayerID"
        static let moveFrom = "moveFrom"
        static let moveTo = "moveTo"
        static let moveSpecial = "moveSpecial"
        static let promotionPieceKind = "promotionPieceKind"
        static let createdAt = "createdAt"
        static let protocolVersion = "protocolVersion"
        static let previousPositionFingerprint = "previousPositionFingerprint"
        static let resultingPositionFingerprint = "resultingPositionFingerprint"
        static let notificationSummary = "notificationSummary"
    }

    static func recordID(gameID: RemoteGameID, sequenceNumber: Int) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(gameID.rawValue)-\(sequenceNumber)")
    }

    static func record(from event: RemoteMoveEvent) -> CKRecord {
        let record = CKRecord(
            recordType: recordType,
            recordID: recordID(gameID: event.gameID, sequenceNumber: event.sequenceNumber)
        )
        apply(event, to: record)
        return record
    }

    static func apply(_ event: RemoteMoveEvent, to record: CKRecord) {
        record[Field.eventID] = event.id.rawValue as CKRecordValue
        record[Field.gameID] = event.gameID.rawValue as CKRecordValue
        record[Field.sequenceNumber] = event.sequenceNumber as CKRecordValue
        record[Field.actorPlayerID] = event.actorPlayerID.rawValue as CKRecordValue
        record[Field.moveFrom] = event.move.from as CKRecordValue
        record[Field.moveTo] = event.move.to as CKRecordValue
        record[Field.createdAt] = event.createdAt as CKRecordValue
        record[Field.protocolVersion] = event.protocolVersion as CKRecordValue
        record[Field.previousPositionFingerprint] = event.previousPositionFingerprint.rawValue as CKRecordValue
        record[Field.resultingPositionFingerprint] = event.resultingPositionFingerprint.rawValue as CKRecordValue
        record[Field.notificationSummary] = event.notificationSummary as CKRecordValue

        switch event.move.special {
        case .none:
            record[Field.moveSpecial] = "none" as CKRecordValue
            record[Field.promotionPieceKind] = nil
        case .castleKingside:
            record[Field.moveSpecial] = "castleKingside" as CKRecordValue
            record[Field.promotionPieceKind] = nil
        case .castleQueenside:
            record[Field.moveSpecial] = "castleQueenside" as CKRecordValue
            record[Field.promotionPieceKind] = nil
        case .enPassant:
            record[Field.moveSpecial] = "enPassant" as CKRecordValue
            record[Field.promotionPieceKind] = nil
        case .promotion(let kind):
            record[Field.moveSpecial] = "promotion" as CKRecordValue
            record[Field.promotionPieceKind] = kind.rawValue as CKRecordValue
        }
    }

    static func event(from record: CKRecord) throws -> RemoteMoveEvent {
        RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: try string(Field.eventID, from: record)),
            gameID: RemoteGameID(rawValue: try string(Field.gameID, from: record)),
            sequenceNumber: try int(Field.sequenceNumber, from: record),
            actorPlayerID: RemotePlayerID(rawValue: try string(Field.actorPlayerID, from: record)),
            move: RemoteEncodedMove(
                from: try string(Field.moveFrom, from: record),
                to: try string(Field.moveTo, from: record),
                special: try special(from: record)
            ),
            createdAt: try date(Field.createdAt, from: record),
            protocolVersion: try int(Field.protocolVersion, from: record),
            previousPositionFingerprint: PositionFingerprint(
                rawValue: try string(Field.previousPositionFingerprint, from: record)
            ),
            resultingPositionFingerprint: PositionFingerprint(
                rawValue: try string(Field.resultingPositionFingerprint, from: record)
            ),
            notificationSummary: try string(Field.notificationSummary, from: record)
        )
    }

    private static func special(from record: CKRecord) throws -> RemoteMoveSpecial {
        let rawSpecial = try string(Field.moveSpecial, from: record)
        switch rawSpecial {
        case "none":
            return .none
        case "castleKingside":
            return .castleKingside
        case "castleQueenside":
            return .castleQueenside
        case "enPassant":
            return .enPassant
        case "promotion":
            let rawKind = try string(Field.promotionPieceKind, from: record)
            guard let kind = Piece.Kind(rawValue: rawKind) else {
                throw Error.invalidPromotionPiece(rawKind)
            }
            return .promotion(kind)
        default:
            throw Error.invalidSpecial(rawSpecial)
        }
    }

    private static func string(_ key: String, from record: CKRecord) throws -> String {
        guard let value = record[key] as? String else {
            throw Error.missingField(key)
        }
        return value
    }

    private static func int(_ key: String, from record: CKRecord) throws -> Int {
        guard let value = record[key] as? Int else {
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
