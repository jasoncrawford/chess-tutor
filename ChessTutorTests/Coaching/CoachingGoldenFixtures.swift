@testable import ChessTutor

enum CoachingGoldenPosition: String, CaseIterable {
    case starting
    case readyToCastle
    case endangeredKnight
    case twoDangerPriorities
    case endangeredPawn
    case protectedPawn
    case winningCapture
    case losingCapture
    case protectPawn
    case createRookThreat
    case cornerKnight
    case exposedQueen
    case harmlessCheck
    case forcedCheck
    case unsupportedEndgame

    var fen: String {
        switch self {
        case .starting:
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        case .readyToCastle:
            "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 0 1"
        case .endangeredKnight:
            "6k1/8/8/8/4p3/5N2/8/6K1 w - - 0 1"
        case .twoDangerPriorities:
            "r5k1/8/8/8/4p3/P4N2/8/6K1 w - - 0 1"
        case .endangeredPawn:
            "6k1/8/1b6/8/8/4P3/8/7K w - - 0 1"
        case .protectedPawn:
            "6k1/8/5n2/8/6P1/7P/8/6K1 w - - 0 1"
        case .winningCapture:
            "k7/5r2/8/8/2B5/8/8/6K1 w - - 0 1"
        case .losingCapture:
            "6k1/5p2/8/8/2B5/8/8/6K1 w - - 0 1"
        case .protectPawn:
            "6k1/8/5n2/8/6P1/8/7P/6K1 w - - 0 1"
        case .createRookThreat:
            "6k1/8/8/8/3r4/8/8/N5K1 w - - 0 1"
        case .cornerKnight:
            "6k1/8/8/8/8/8/8/N5K1 w - - 0 1"
        case .exposedQueen:
            "3r2k1/8/8/8/8/8/8/3Q2K1 w - - 0 1"
        case .harmlessCheck:
            "r5k1/8/8/8/8/8/8/1N4K1 w - - 0 1"
        case .forcedCheck:
            "k3r3/8/8/1B6/8/8/8/4K3 w - - 0 1"
        case .unsupportedEndgame:
            "7k/8/8/8/3K4/8/8/8 w - - 0 1"
        }
    }

    var state: GameState { CoachingFENParser.parse(fen) }
}

enum CoachingGoldenCase: String, CaseIterable {
    case t1Entry, t1BlockedRook, t1FlankPawn, t1Hint, t1KnightSelected
    case t1PreferredKnight, t1EdgeKnight, t1CenterPawn
    case t2Entry, t2OneSquareKingMove, t2KnightSwitch, t2Castle
    case t3Entry, t3WrongOwnPiece, t3Target, t3WrongAttacker, t3Attacker
    case t3UnresolvedMove, t3ResolvedMove
    case t4LowerPriorityPawn, t4PrimaryKnight
    case t5PawnDanger, t5PawnResolved, t5ProtectedTap, t5ProtectedAbsence
    case t6WrongSource, t6Hint, t6Capture
    case t7UnsafeCapture, t7NoSafeCapture
    case t8AddsDefender
    case t9Entry, t9Hint, t9Completed
    case t10Entry, t10Completed
    case t11Safe, t11QueenLoss, t11IncorrectLooksSafe, t11HarmlessCheck
    case t12CheckLocate, t12WrongChecker, t12Capture, t12Block, t12KingMove
    case t12UnsupportedEntry, t12UnsupportedSafeMove
}

enum CoachingGoldenMoves {
    static let castle = Move(from: sq("e1"), to: sq("g1"), special: .castleKingside)
    static let knightTaken = Move(from: sq("e4"), to: sq("f3"))
    static let pawnTaken = Move(from: sq("a8"), to: sq("a3"))
    static let pawnEscapes = Move(from: sq("e3"), to: sq("e4"))
    static let bishopWinsRook = Move(from: sq("c4"), to: sq("f7"))
    static let bishopTakesPawn = Move(from: sq("c4"), to: sq("f7"))
    static let kingTakesBishop = Move(from: sq("g8"), to: sq("f7"))
    static let addsPawnDefender = Move(from: sq("h2"), to: sq("h3"))
    static let knightTakesPawn = Move(from: sq("f6"), to: sq("g4"))
    static let pawnRecapturesKnight = Move(from: sq("h3"), to: sq("g4"))
    static let knightThreatB3 = Move(from: sq("a1"), to: sq("b3"))
    static let knightThreatC2 = Move(from: sq("a1"), to: sq("c2"))
    static let exposesQueen = Move(from: sq("d1"), to: sq("d4"))
    static let rookTakesQueen = Move(from: sq("d8"), to: sq("d4"))
    static let developsKnight = Move(from: sq("b1"), to: sq("c3"))
    static let rookChecks = Move(from: sq("a8"), to: sq("a1"))
    static let capturesChecker = Move(from: sq("b5"), to: sq("e8"))
    static let blocksChecker = Move(from: sq("b5"), to: sq("e2"))
}

struct CoachingGoldenTurn: Equatable {
    let observation: String?
    let primaryMessage: String
    let instruction: String?
    let actions: [CoachingAction]
    let actionTitles: [String]
    let boardTask: CoachingBoardTask
    let routine: [CoachingRoutineState]
    let emphasizedSquares: Set<Square>
    let candidateSquares: Set<Square>
    let paths: Set<CoachFocusPath>
}

func sq(_ algebraic: String) -> Square {
    let bytes = Array(algebraic.utf8)
    precondition(bytes.count == 2, "Expected an algebraic square such as e4")
    guard let file = Square.File(rawValue: Int(bytes[0]) - 96),
          let rank = Int(String(UnicodeScalar(bytes[1]))) else {
        preconditionFailure("Invalid algebraic square: \(algebraic)")
    }
    return Square(file: file, rank: rank)
}

enum CoachingFENParser {
    static func parse(_ fen: String) -> GameState {
        let fields = fen.split(separator: " ")
        precondition(fields.count == 6, "FEN must contain six fields")
        precondition(Int(fields[4]) != nil && Int(fields[5]) != nil,
                     "FEN clocks must be integers")

        let ranks = fields[0].split(separator: "/")
        precondition(ranks.count == 8, "FEN must contain eight ranks")
        var pieces: [Square: Piece] = [:]
        for (rankOffset, encodedRank) in ranks.enumerated() {
            var file = 1
            for token in encodedRank {
                if let emptyCount = token.wholeNumberValue {
                    file += emptyCount
                    continue
                }
                guard let squareFile = Square.File(rawValue: file),
                      let piece = piece(for: token) else {
                    preconditionFailure("Invalid FEN board field: \(fields[0])")
                }
                pieces[Square(file: squareFile, rank: 8 - rankOffset)] = piece
                file += 1
            }
            precondition(file == 9, "Each FEN rank must describe eight files")
        }

        let sideToMove: PieceColor
        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: preconditionFailure("Invalid FEN side to move")
        }

        let rightsField = fields[2]
        precondition(rightsField == "-" || rightsField.allSatisfy("KQkq".contains),
                     "Invalid FEN castling rights")
        let rights = CastlingRights(
            whiteKingside: rightsField.contains("K"),
            whiteQueenside: rightsField.contains("Q"),
            blackKingside: rightsField.contains("k"),
            blackQueenside: rightsField.contains("q")
        )
        let enPassant = fields[3] == "-" ? nil : sq(String(fields[3]))
        return GameState(
            board: Board(pieces: pieces),
            sideToMove: sideToMove,
            castlingRights: rights,
            enPassantTarget: enPassant
        )
    }

    private static func piece(for token: Character) -> Piece? {
        let color: PieceColor = token.isUppercase ? .white : .black
        let kind: Piece.Kind
        switch token.lowercased() {
        case "k": kind = .king
        case "q": kind = .queen
        case "r": kind = .rook
        case "b": kind = .bishop
        case "n": kind = .knight
        case "p": kind = .pawn
        default: return nil
        }
        return Piece(kind: kind, color: color)
    }
}
