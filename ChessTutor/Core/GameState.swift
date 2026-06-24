struct CastlingRights: Equatable, Sendable {
    var whiteKingside = false
    var whiteQueenside = false
    var blackKingside = false
    var blackQueenside = false
}

struct GameState: Equatable, Sendable {
    var board: Board
    var sideToMove: PieceColor
    var moveHistory: [Move]
    var result: GameResult
    var castlingRights: CastlingRights
    var enPassantTarget: Square?

    init(
        board: Board,
        sideToMove: PieceColor,
        moveHistory: [Move] = [],
        result: GameResult = .ongoing,
        castlingRights: CastlingRights = CastlingRights(),
        enPassantTarget: Square? = nil
    ) {
        self.board = board
        self.sideToMove = sideToMove
        self.moveHistory = moveHistory
        self.result = result
        self.castlingRights = castlingRights
        self.enPassantTarget = enPassantTarget
    }

    static func startingPosition() -> GameState {
        GameState(
            board: .startingPosition(),
            sideToMove: .white,
            castlingRights: CastlingRights(
                whiteKingside: true,
                whiteQueenside: true,
                blackKingside: true,
                blackQueenside: true
            )
        )
    }

    func applyingUnchecked(_ move: Move) -> GameState {
        var next = self
        guard let movingPiece = next.board[move.from] else {
            return next
        }
        let capturedPiece = next.board[move.to]
        next.board[move.from] = nil

        switch move.special {
        case .castleKingside:
            next.board[move.to] = movingPiece
            let rank = move.from.rank
            let rookFrom = Square(file: .h, rank: rank)
            let rookTo = Square(file: .f, rank: rank)
            next.board[rookTo] = next.board[rookFrom]
            next.board[rookFrom] = nil
        case .castleQueenside:
            next.board[move.to] = movingPiece
            let rank = move.from.rank
            let rookFrom = Square(file: .a, rank: rank)
            let rookTo = Square(file: .d, rank: rank)
            next.board[rookTo] = next.board[rookFrom]
            next.board[rookFrom] = nil
        case .enPassant:
            next.board[move.to] = movingPiece
            let capturedPawn = Square(file: move.to.file, rank: move.from.rank)
            next.board[capturedPawn] = nil
        case .promotion(let promotedKind):
            next.board[move.to] = Piece(kind: promotedKind, color: movingPiece.color)
        case nil:
            next.board[move.to] = movingPiece
        }

        next.updateCastlingRights(for: movingPiece, from: move.from, capturedPiece: capturedPiece, capturedAt: move.to)
        next.enPassantTarget = nil
        if movingPiece.kind == .pawn, abs(move.to.rank - move.from.rank) == 2 {
            next.enPassantTarget = Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)
        }
        next.moveHistory.append(move)
        next.sideToMove = sideToMove.opposite
        return next
    }

    mutating func apply(_ move: Move) {
        self = applyingUnchecked(move)
        let legalReplies = LegalMoveGenerator.allLegalMoves(in: self)
        if legalReplies.isEmpty {
            if LegalMoveGenerator.isKingInCheck(sideToMove, in: board) {
                result = .checkmate(winner: sideToMove.opposite)
            } else {
                result = .stalemate
            }
        } else {
            result = .ongoing
        }
    }

    private mutating func updateCastlingRights(for piece: Piece, from: Square, capturedPiece: Piece?, capturedAt: Square) {
        if piece.kind == .king {
            switch piece.color {
            case .white:
                castlingRights.whiteKingside = false
                castlingRights.whiteQueenside = false
            case .black:
                castlingRights.blackKingside = false
                castlingRights.blackQueenside = false
            }
        }

        if piece.kind == .rook {
            clearCastlingRight(forRookAt: from, color: piece.color)
        }

        if capturedPiece?.kind == .rook, let capturedColor = capturedPiece?.color {
            clearCastlingRight(forRookAt: capturedAt, color: capturedColor)
        }
    }

    private mutating func clearCastlingRight(forRookAt square: Square, color: PieceColor) {
        switch (color, square.file, square.rank) {
        case (.white, .h, 1):
            castlingRights.whiteKingside = false
        case (.white, .a, 1):
            castlingRights.whiteQueenside = false
        case (.black, .h, 8):
            castlingRights.blackKingside = false
        case (.black, .a, 8):
            castlingRights.blackQueenside = false
        default:
            break
        }
    }
}
