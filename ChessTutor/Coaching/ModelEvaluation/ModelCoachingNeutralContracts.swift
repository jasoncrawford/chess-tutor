struct ModelCoachingNeutralSnapshot: Equatable, Sendable {
    let committedState: GameState
    let learner: PieceColor
    let positionRevision: Int
    let selectedSquare: Square?
    let tentativeMove: Move?
    let latestEvent: ModelCoachingNeutralEpisodeEvent
    let episodeEvents: [ModelCoachingNeutralEpisodeEvent]
}

struct ModelCoachingNeutralEpisodeEvent: Codable, Equatable, Sendable {
    let sequence: Int
    let kind: ModelCoachingLearnerEventKind
    let referencedIDs: [String]
}

struct ModelCoachingNeutralRequest: Codable, Equatable, Sendable {
    let schemaVersion: String
    let requestID: String
    let positionRevision: Int
    let position: ModelCoachingPosition
    let gameHistory: [ModelCoachingHistoryMove]
    let interaction: ModelCoachingNeutralInteraction
    let pieces: [ModelCoachingNeutralPiece]
    let legalMoves: [ModelCoachingNeutralMove]
    let occupiedSquareRelationships: [ModelCoachingNeutralRelationship]
    let tentativeReplies: [ModelCoachingNeutralReply]
    let capabilities: ModelCoachingNeutralCapabilities
}

struct ModelCoachingNeutralInteraction: Codable, Equatable, Sendable {
    let selectedSquare: String?
    let selectedPieceReference: String?
    let tentativeMove: ModelCoachingNeutralMove?
    let latestEvent: ModelCoachingNeutralEpisodeEvent
    let episodeEvents: [ModelCoachingNeutralEpisodeEvent]
}

struct ModelCoachingNeutralPiece: Codable, Equatable, Sendable {
    let id: String
    let color: String
    let kind: String
    let square: String
}

struct ModelCoachingNeutralMove: Codable, Equatable, Sendable {
    let id: String
    let san: String
    let canonicalMove: String
    let sourcePieceReference: String
    let destinationSquare: String
    let capturePieceReference: String?
    let special: String
    let isLegal: Bool
    let givesCheck: Bool
    let givesCheckmate: Bool
}

struct ModelCoachingNeutralRelationship: Codable, Equatable, Sendable {
    let id: String
    let kind: ModelCoachingRelationshipKind
    let sourcePieceReference: String
    let targetPieceReference: String
}

typealias ModelCoachingNeutralReply = ModelCoachingNeutralMove

struct ModelCoachingNeutralCapabilities: Codable, Equatable, Sendable {
    let canSelectBoardPiece: Bool
    let canInspectSquare: Bool
    let canStageMove: Bool
    let canReplaceMove: Bool
    let canRemoveMove: Bool
}

struct ModelCoachingNeutralTurn: Codable, Equatable, Sendable {
    let message: String
    let actions: [String]
    let focus: [String]
}
