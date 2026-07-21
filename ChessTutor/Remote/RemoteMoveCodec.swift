enum RemoteMoveSpecial: Codable, Equatable, Sendable {
    case none
    case castleKingside
    case castleQueenside
    case enPassant
    case promotion(Piece.Kind)
}

struct RemoteEncodedMove: Codable, Equatable, Sendable {
    let from: String
    let to: String
    let special: RemoteMoveSpecial
}

enum RemoteMoveCodec {
    enum Error: Swift.Error, Equatable {
        case invalidSquare(String)
    }

    static func encode(_ move: Move) -> RemoteEncodedMove {
        RemoteEncodedMove(
            from: encode(move.from),
            to: encode(move.to),
            special: encode(move.special)
        )
    }

    static func encodeSquare(_ square: Square) -> String {
        encode(square)
    }

    static func decode(_ encoded: RemoteEncodedMove) throws -> Move {
        Move(
            from: try decodeSquare(encoded.from),
            to: try decodeSquare(encoded.to),
            special: decode(encoded.special)
        )
    }

    private static func encode(_ square: Square) -> String {
        "\(fileLetter(for: square.file))\(square.rank)"
    }

    private static func decodeSquare(_ value: String) throws -> Square {
        guard value.count == 2,
              let fileCharacter = value.first,
              let rankCharacter = value.last,
              let file = file(for: fileCharacter),
              let rank = Int(String(rankCharacter)),
              (1...8).contains(rank) else {
            throw Error.invalidSquare(value)
        }
        return Square(file: file, rank: rank)
    }

    private static func encode(_ special: Move.Special?) -> RemoteMoveSpecial {
        switch special {
        case .castleKingside:
            return .castleKingside
        case .castleQueenside:
            return .castleQueenside
        case .enPassant:
            return .enPassant
        case .promotion(let kind):
            return .promotion(kind)
        case nil:
            return .none
        }
    }

    private static func decode(_ special: RemoteMoveSpecial) -> Move.Special? {
        switch special {
        case .none:
            return nil
        case .castleKingside:
            return .castleKingside
        case .castleQueenside:
            return .castleQueenside
        case .enPassant:
            return .enPassant
        case .promotion(let kind):
            return .promotion(kind)
        }
    }

    private static func fileLetter(for file: Square.File) -> String {
        switch file {
        case .a: return "a"
        case .b: return "b"
        case .c: return "c"
        case .d: return "d"
        case .e: return "e"
        case .f: return "f"
        case .g: return "g"
        case .h: return "h"
        }
    }

    private static func file(for character: Character) -> Square.File? {
        switch character {
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        default: return nil
        }
    }
}
