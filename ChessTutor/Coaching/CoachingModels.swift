struct CoachingRequest: Equatable, Sendable {
    enum Context: Equatable, Sendable {
        case start
        case tentativeMove(origin: CoachingMoveOrigin)
    }

    let committedState: GameState
    let tentativeMove: Move?
    let learner: PieceColor
    let positionRevision: Int
    let context: Context
}

enum CoachingMoveOrigin: Equatable, Sendable {
    case preexisting
    case check
    case safe
    case take
    case wake
    case fallback
}

protocol CoachingAdvising: Sendable {
    func advice(for request: CoachingRequest) async throws -> CoachingAdvice
}

enum CoachingConfidence: Equatable, Sendable {
    case high
    case unsupported
}

struct CoachingCaptureEstimate: Equatable, Sendable {
    let move: Move
    let capturedPiece: Piece
    let capturedSquare: Square
    let immediateRecapture: Move?
    let netGainForMover: Int
}

struct CoachingUrgentProblem: Equatable, Sendable {
    let target: Square
    let piece: Piece
    let captures: [CoachingCaptureEstimate]
    let worstEstimatedLoss: Int
}

enum CoachingOpponentIssueSeverity: Equatable, Sendable {
    case notice
    case reviseMove
}

enum CoachingOpponentIssueKind: Equatable, Sendable {
    case mateInOne
    case check
    case materialLoss(points: Int)
}

struct CoachingOpponentIssue: Equatable, Sendable {
    let reply: Move
    let kind: CoachingOpponentIssueKind
    let severity: CoachingOpponentIssueSeverity
    let answerSquares: Set<Square>
}

struct CoachingMoveAssessment: Equatable, Sendable {
    let move: Move
    let isLegal: Bool
    let resolvesRequiredDanger: Bool
    let opponentIssues: [CoachingOpponentIssue]
    let concepts: [CoachingConcept]
    let isAcceptable: Bool
}

enum CoachingConcept: Equatable, Hashable, Sendable {
    case kingInCheck
    case pieceNeedsHelp
    case checkingPiece
    case profitableAttacker
    case profitableCapture
    case mateInOne
    case captureResolvesDanger
    case developsKnightOrBishop
    case advancesCenterPawn
    case castlesForKingSafety
    case addsUsefulDefender
    case createsSafeImmediateThreat
    case improvesCentralActivity
    case allowsCheck
    case allowsMateInOne
    case allowsMaterialLoss
    case safeAfterReplyCheck
}

enum CoachingEvidence: Equatable, Sendable {
    case check(attackers: Set<Square>)
    case danger(target: Square, estimatedLoss: Int)
    case capture(CoachingCaptureEstimate)
    case development(source: Square, destination: Square)
    case centerPawn(source: Square, destination: Square)
    case castle(Move)
    case defender(source: Square, target: Square)
    case threat(source: Square, target: Square)
    case mobility(source: Square, destination: Square, before: Int, after: Int)
    case opponentReply(CoachingOpponentIssue)
    case verifiedSafe
}

struct CoachingInsight: Equatable, Sendable {
    let concept: CoachingConcept
    let subjectSquares: Set<Square>
    let candidateMoves: [Move]
    let priority: Int
    let confidence: CoachingConfidence
    let evidence: CoachingEvidence
}

struct CoachingOpportunity: Equatable, Sendable {
    let concept: CoachingConcept
    let subjectSquares: Set<Square>
    let moves: [Move]
    let priority: Int
    let evidence: CoachingEvidence
}

struct CoachingEvaluation: Equatable, Sendable {
    let request: CoachingRequest
    let checkingPieces: Set<Square>
    let opponentHasAnyLegalCapture: Bool
    let learnerHasAnyLegalCapture: Bool
    let opponentCaptureEstimates: [CoachingCaptureEstimate]
    let urgentProblems: [CoachingUrgentProblem]
    let learnerCaptureEstimates: [CoachingCaptureEstimate]
    let mateInOneMoves: Set<Move>
    let moveAssessments: [Move: CoachingMoveAssessment]
}

struct CoachingAdvice: Equatable, Sendable {
    let evaluation: CoachingEvaluation
    let insights: [CoachingInsight]
    let urgentProblems: [CoachingUrgentProblem]
    let takeOpportunities: [CoachingOpportunity]
    let wakeOpportunities: [CoachingOpportunity]
    let moveAssessments: [Move: CoachingMoveAssessment]
    let openingDevelopmentIsRelevant: Bool
    let confidence: CoachingConfidence

    var checkingPieces: Set<Square> { evaluation.checkingPieces }
}
