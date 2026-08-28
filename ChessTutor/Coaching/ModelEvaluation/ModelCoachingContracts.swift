struct ModelCoachingRequest: Codable, Equatable, Sendable {
    let schemaVersion: String
    let promptVersion: String
    let requestID: String
    let positionRevision: Int
    let currentPosition: ModelCoachingPosition
    let fullGameHistory: [ModelCoachingHistoryMove]
    let currentInteraction: ModelCoachingInteraction
    let currentTurnCoachingHistory: [ModelCoachingHistoryEntry]
    let chessEvidence: ModelCoachingEvidenceBundle
    let permittedReferences: ModelCoachingPermittedReferences
}

struct ModelCoachingTurn: Codable, Equatable, Sendable {
    let schemaVersion: String
    let requestID: String
    let teachingIntent: ModelCoachingTeachingIntent
    let primaryMessage: String
    let instruction: String?
    let responseToLatestAction: String?
    let actionReferences: [String]
    let boardTaskReference: String?
    let boardFocusReferences: [String]
    let relationshipReferences: [String]
    let supportingEvidenceReferences: [String]
}

struct ModelCoachingPosition: Codable, Equatable, Sendable {
    let fen: String
    let sideToMove: String
    let status: String
}

struct ModelCoachingHistoryMove: Codable, Equatable, Sendable {
    let ply: Int
    let canonicalMove: String
    let displayNotation: String
}

struct ModelCoachingInteraction: Codable, Equatable, Sendable {
    let selectedPieceReference: String?
    let tentativeMoveReference: String?
    let latestEvent: ModelCoachingLearnerEvent
    let availableOperationReferences: [ModelCoachingOperation]
}

struct ModelCoachingLearnerEvent: Codable, Equatable, Sendable {
    let kind: ModelCoachingLearnerEventKind
    let referencedIDs: [String]
}

struct ModelCoachingHistoryEntry: Codable, Equatable, Sendable {
    let sequence: Int
    let kind: ModelCoachingHistoryKind
    let summary: String
    let referencedIDs: [String]
}

struct ModelCoachingEvidenceBundle: Codable, Equatable, Sendable {
    let scope: ModelCoachingEvidenceScope
    let pieces: [ModelCoachingPieceReference]
    let legalMoves: [ModelCoachingMoveReference]
    let relationships: [ModelCoachingRelationshipReference]
    let immediateReplies: [ModelCoachingReplyReference]
    let tacticalFacts: [ModelCoachingTacticalFact]
}

struct ModelCoachingEvidenceScope: Codable, Equatable, Sendable {
    let legalMoves: ModelCoachingEvidenceScopeKind
    let relationships: ModelCoachingEvidenceScopeKind
    let immediateReplies: ModelCoachingEvidenceScopeKind
}

struct ModelCoachingPieceReference: Codable, Equatable, Sendable {
    let id: String
    let color: String
    let kind: String
    let square: String
}

struct ModelCoachingMoveReference: Codable, Equatable, Sendable {
    let id: String
    let canonicalMove: String
    let sourcePieceReference: String
    let destinationSquare: String
    let capturePieceReference: String?
    let special: String
    let isLegal: Bool
}

struct ModelCoachingRelationshipReference: Codable, Equatable, Sendable {
    let id: String
    let kind: ModelCoachingRelationshipKind
    let sourceReference: String
    let targetReference: String
}

struct ModelCoachingReplyReference: Codable, Equatable, Sendable {
    let id: String
    let afterMoveReference: String
    let replyMoveReference: String
    let checkingPieceReferences: [String]
    let capturedPieceReference: String?
    let netMaterialGain: Int?
}

struct ModelCoachingTacticalFact: Codable, Equatable, Sendable {
    let id: String
    let kind: ModelCoachingTacticalFactKind
    let subjectReferences: [String]
    let integerValue: Int?
}

struct ModelCoachingPermittedReferences: Codable, Equatable, Sendable {
    let actions: [ModelCoachingPermittedAction]
    let boardTasks: [ModelCoachingPermittedBoardTask]
    let boardFocus: [String]
    let relationships: [String]
    let evidence: [String]
}

struct ModelCoachingPermittedAction: Codable, Equatable, Sendable {
    let id: String
    let kind: ModelCoachingActionKind
    let title: String
}

struct ModelCoachingPermittedBoardTask: Codable, Equatable, Sendable {
    let id: String
    let kind: ModelCoachingBoardTaskKind
}

enum ModelCoachingEvidenceScopeKind: String, Codable, Equatable, Sendable {
    case exhaustive
    case bounded
}

enum ModelCoachingRelationshipKind: String, Codable, Equatable, Sendable {
    case attacks
    case defends
    case checks
    case canCapture
    case canRecapture
}

enum ModelCoachingTacticalFactKind: String, Codable, Equatable, Sendable {
    case inCheck
    case checkmate
    case stalemate
    case dangerLoss
    case exchangeGain
    case mateInOne
}

enum ModelCoachingActionKind: String, Codable, Equatable, Sendable {
    case hint
    case noPieceNeedsHelp
    case noSafeCapture
    case looksSafe
    case playMove
    case tryAnotherMove
    case closeHelp
}

enum ModelCoachingBoardTaskKind: String, Codable, Equatable, Sendable {
    case none
    case identifyPiece
    case inspectRelationship
    case movePiece
    case confirmMove
}

enum ModelCoachingLearnerEventKind: String, Codable, Equatable, Sendable {
    case helpOpened
    case helpReopened
    case pieceSelected
    case squareInspected
    case moveStaged
    case moveReplaced
    case moveRemoved
    case actionChosen
    case helpClosed
}

enum ModelCoachingHistoryKind: String, Codable, Equatable, Sendable {
    case learnerEvent
    case tutorTurn
    case supersededRequest
}

enum ModelCoachingOperation: String, Codable, Equatable, Sendable {
    case selectBoardPiece
    case inspectSquare
    case stageMove
    case replaceMove
    case removeMove
    case hint
    case noPieceNeedsHelp
    case noSafeCapture
    case looksSafe
    case playMove
    case tryAnotherMove
    case closeHelp
}

enum ModelCoachingTeachingIntent: String, Codable, Equatable, Sendable {
    case orient
    case scanDanger
    case scanCapture
    case chooseMove
    case evaluateMove
    case reviseMove
    case confirmMove
    case resolveCheck
    case findMate
    case other
}

struct ModelCoachingLimits: Codable, Equatable, Sendable {
    let primaryWords: Int
    let instructionWords: Int
    let responseWords: Int
    let actionTitleWords: Int
    let actionCount: Int

    static let `default` = ModelCoachingLimits(
        primaryWords: 18,
        instructionWords: 14,
        responseWords: 16,
        actionTitleWords: 5,
        actionCount: 3
    )
}
