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

enum CoachingAction: Equatable, Hashable, Sendable {
    case noAnswer
    case looksSafe
    case hint
    case stop
    case done
    case keepLooking
}

enum CoachingBoardTask: Equatable, Sendable {
    case none
    case identify(allowsMoveRevision: Bool)
    case move
}

enum CoachingWakePurpose: Equatable, Sendable {
    case openingDevelopment(firstMove: Bool)
    case addsDefender
    case createsThreat
    case centralActivity
    case castle
}

enum CoachingPrompt: Equatable, Sendable {
    case checkLocate
    case checkResolve
    case safeLocate
    case safeIdentifyAttacker(piece: Piece.Kind)
    case safeResolve(target: Piece.Kind, attacker: Piece.Kind)
    case takeChooseMove
    case wakeChoosePiece(purpose: CoachingWakePurpose)
    case wakeChooseMove(piece: Piece.Kind, purpose: CoachingWakePurpose)
    case opponentReply(opponent: PieceColor)
    case fallbackChooseMove
    case reviseMove
    case illegalKingSafety
    case complete(origin: CoachingMoveOrigin, idea: CoachingCompletionIdea)
}

enum CoachingCompletionIdea: Equatable, Sendable {
    case resolvesDanger(piece: Piece.Kind)
    case mate
    case profitableCapture(captured: Piece.Kind)
    case develops(piece: Piece.Kind)
    case advancesCenterPawn
    case castles
    case addsDefender(piece: Piece.Kind)
    case createsThreat(piece: Piece.Kind)
    case centralizes(piece: Piece.Kind)
    case verifiedSafe
}

enum CoachingFeedback: Equatable, Sendable {
    case safePiece(piece: Piece.Kind)
    case lowerPriorityThreat(piece: Piece.Kind, urgentPiece: Piece.Kind)
    case nonurgentThreat(piece: Piece.Kind)
    case expectedLearnerPiece
    case notCheckingPiece(piece: Piece.Kind?)
    case notAttacker(piece: Piece.Kind, target: Piece.Kind)
    case expectedAttacker(target: Piece.Kind)
    case blockedWakePiece(piece: Piece.Kind)
    case notWakeCandidate(piece: Piece.Kind, purpose: CoachingWakePurpose)
    case notReplyIssue
    case correctAbsence
    case missedExistingAnswer
    case concreteFlaw(kind: CoachingOpponentIssueKind, affectedPiece: Piece.Kind?)
    case dangerStillPresent(attacker: Piece.Kind?, target: Piece.Kind)
    case noRecognizedPurpose(purpose: CoachingWakePurpose?)
    case harmlessCheckFound
    case checkFoundOtherDangerRemains
}

enum CoachingRoutineState: Equatable, Sendable {
    case safeCurrent, safeCleared
    case takePending, takeCurrent, takeCleared
    case wakePending, wakeCurrent, wakeCleared
}

struct CoachFocusPath: Equatable, Hashable, Sendable {
    enum Role: Equatable, Hashable, Sendable { case attacker, candidate }
    let source: Square
    let destination: Square
    let role: Role
}

struct CoachFocusPresentation: Equatable, Sendable {
    static let empty = CoachFocusPresentation(
        emphasizedSquares: [], candidateSquares: [], paths: [], pulseID: 0
    )
    let emphasizedSquares: Set<Square>
    let candidateSquares: Set<Square>
    let paths: Set<CoachFocusPath>
    let pulseID: Int
}

enum CoachingActionProminence: Equatable, Sendable {
    case primary
    case secondary
    case quiet
}

enum CoachingHint: Equatable, Sendable {
    case checkMarker
    case dangerMarker
    case replyMarkers
    case candidatePieces
    case attackerRelationship
    case safeResponseIdeas
    case movementMarkers
    case candidateMoves
}

struct CoachingActionPresentation: Equatable, Sendable {
    let action: CoachingAction
    let title: String
    let accessibilityLabel: String
    let prominence: CoachingActionProminence
}

struct CoachingPresentationContext: Equatable, Sendable {
    let prompt: CoachingPrompt
    let feedback: CoachingFeedback?
    let learner: PieceColor
    let hint: CoachingHint?
    let missesAtCurrentLevel: Int
    let routine: [CoachingRoutineState]
    let actions: [CoachingAction]
    let boardTask: CoachingBoardTask
    let focus: CoachFocusPresentation
}

struct CoachingPresentation: Equatable, Sendable {
    let headline: String
    let instruction: String?
    let hint: CoachingHint?
    let routine: [CoachingRoutineState]
    let actions: [CoachingActionPresentation]
    let boardTask: CoachingBoardTask
    let focus: CoachFocusPresentation
}

protocol CoachingExplaining: Sendable {
    func presentation(for context: CoachingPresentationContext) -> CoachingPresentation
}
