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

struct CoachingExchangeFact: Equatable, Sendable {
    let move: Move
    let mover: Piece.Kind
    let captured: Piece.Kind
    let immediateRecapture: Move?
    let immediateRecapturer: Piece.Kind?
    let netGainForLearner: Int
}

struct CoachingDangerProblem: Equatable, Sendable {
    let target: Square
    let piece: Piece
    let pieceValue: Int
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
    let affectedSquare: Square?
    let checkingSquares: Set<Square>

    var answerSquares: Set<Square> { [reply.from] }
}

struct CoachingOpponentActivity: Equatable, Sendable {
    let reply: Move
    let opponentPiece: Piece.Kind
    let checkingSquares: Set<Square>
    let capturedSquare: Square?
    let capturedPiece: Piece.Kind?
    let netGainForOpponent: Int?
    let immediateRecapture: Move?
    let isMate: Bool

    var isCheck: Bool { !checkingSquares.isEmpty }
    var canWinPiece: Bool { (netGainForOpponent ?? 0) >= 1 }
    var isQuestionAnswer: Bool { isCheck || canWinPiece }
}

struct CoachingOpponentReplyFact: Equatable, Sendable {
    let issue: CoachingOpponentIssue
    let opponentPiece: Piece.Kind
    let affectedPiece: Piece.Kind?
    let learnerPiece: Piece.Kind?
}

struct CoachingMoveAssessment: Equatable, Sendable {
    let move: Move
    let isLegal: Bool
    let resolvesRequiredDanger: Bool
    let opponentIssues: [CoachingOpponentIssue]
    let opponentActivities: [CoachingOpponentActivity]
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

enum CoachingCandidateGrade: Equatable, Sendable {
    case preferred
    case acceptable
}

enum CoachingCentralityComparison: Equatable, Sendable {
    case closerWithMoreMobility(
        alternative: Move,
        candidateMobility: Int,
        alternativeMobility: Int
    )
    case fartherWithLessMobility(
        alternative: Move,
        candidateMobility: Int,
        alternativeMobility: Int
    )
}

struct CoachingCandidateMove: Equatable, Sendable {
    let move: Move
    let grade: CoachingCandidateGrade
    let resultingMobility: Int?
    let centralityComparison: CoachingCentralityComparison?

    init(
        move: Move,
        grade: CoachingCandidateGrade,
        resultingMobility: Int? = nil,
        centralityComparison: CoachingCentralityComparison? = nil
    ) {
        self.move = move
        self.grade = grade
        self.resultingMobility = resultingMobility
        self.centralityComparison = centralityComparison
    }
}

enum CoachingWakeTask: Equatable, Sendable {
    case opening(
        firstMove: Bool,
        castleIsAlternative: Bool,
        candidates: [CoachingCandidateMove]
    )
    case castle(move: Move)
    case protect(
        source: Square,
        sourcePiece: Piece.Kind,
        target: Square,
        targetPiece: Piece.Kind,
        candidates: [CoachingCandidateMove]
    )
    case createThreat(
        source: Square,
        sourcePiece: Piece.Kind,
        target: Square,
        targetPiece: Piece.Kind,
        candidates: [CoachingCandidateMove]
    )
    case improveMobility(
        source: Square,
        piece: Piece.Kind,
        sourceIsCorner: Bool,
        before: Int,
        candidates: [CoachingCandidateMove]
    )

    var candidates: [CoachingCandidateMove] {
        switch self {
        case let .opening(_, _, candidates),
             let .protect(_, _, _, _, candidates),
             let .createThreat(_, _, _, _, candidates),
             let .improveMobility(_, _, _, _, candidates):
            candidates
        case .castle:
            []
        }
    }
}

struct CoachingEvaluation: Equatable, Sendable {
    let request: CoachingRequest
    let checkingPieces: Set<Square>
    let opponentHasAnyLegalCapture: Bool
    let learnerHasAnyLegalCapture: Bool
    let opponentCaptureEstimates: [CoachingCaptureEstimate]
    let dangerProblems: [CoachingDangerProblem]
    let learnerCaptureEstimates: [CoachingCaptureEstimate]
    let mateInOneMoves: Set<Move>
    let moveAssessments: [Move: CoachingMoveAssessment]
}

struct CoachingAdvice: Equatable, Sendable {
    let evaluation: CoachingEvaluation
    let insights: [CoachingInsight]
    let dangerProblems: [CoachingDangerProblem]
    let takeOpportunities: [CoachingOpportunity]
    let wakeOpportunities: [CoachingOpportunity]
    let wakeTasks: [CoachingWakeTask]
    let moveAssessments: [Move: CoachingMoveAssessment]
    let openingDevelopmentIsRelevant: Bool
    let confidence: CoachingConfidence

    init(
        evaluation: CoachingEvaluation,
        insights: [CoachingInsight],
        dangerProblems: [CoachingDangerProblem],
        takeOpportunities: [CoachingOpportunity],
        wakeOpportunities: [CoachingOpportunity],
        wakeTasks: [CoachingWakeTask] = [],
        moveAssessments: [Move: CoachingMoveAssessment],
        openingDevelopmentIsRelevant: Bool,
        confidence: CoachingConfidence
    ) {
        self.evaluation = evaluation
        self.insights = insights
        self.dangerProblems = dangerProblems
        self.takeOpportunities = takeOpportunities
        self.wakeOpportunities = wakeOpportunities
        self.wakeTasks = wakeTasks
        self.moveAssessments = moveAssessments
        self.openingDevelopmentIsRelevant = openingDevelopmentIsRelevant
        self.confidence = confidence
    }

    var checkingPieces: Set<Square> { evaluation.checkingPieces }

    var exchangeFact: CoachingExchangeFact? {
        evaluation.request.tentativeMove.flatMap { evaluation.exchangeFacts[$0] }
    }

    func exchangeFact(for move: Move) -> CoachingExchangeFact? {
        evaluation.exchangeFacts[move]
    }

    func grade(for move: Move) -> CoachingCandidateGrade? {
        wakeTasks.lazy
            .flatMap(\.candidates)
            .first(where: { $0.move == move })?
            .grade
    }

    var primaryDangerProblems: [CoachingDangerProblem] {
        guard let first = dangerProblems.first else { return [] }
        return dangerProblems.filter {
            $0.worstEstimatedLoss == first.worstEstimatedLoss
                && $0.pieceValue == first.pieceValue
        }
    }
}

enum CoachingAction: Equatable, Hashable, Sendable {
    case noAnswer
    case looksSafe
    case hint
    case stop
    case done
    case keepLooking
}

enum CoachingAbsenceKind: Equatable, Sendable {
    case noPieceNeedsHelp
    case noSafeCapture
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
    case wake(task: CoachingWakeTask, selectedPiece: Piece.Kind?)
    case opponentReply(opponent: PieceColor)
    case fallbackChooseMove
    case unsupportedFallbackChooseMove
    case opponentIssueRevise(
        kind: CoachingOpponentIssueKind,
        affectedPiece: Piece.Kind?
    )
    case reviseMove
    case illegalKingSafety
    case complete(origin: CoachingMoveOrigin, idea: CoachingCompletionIdea)
}

enum CoachingCompletionIdea: Equatable, Sendable {
    case resolvesDanger(CoachingDangerResolution)
    case resolvesCheck(resolution: CoachingCheckResolution, checker: Piece.Kind?)
    case mate
    case profitableCapture(captured: Piece.Kind)
    case safeCapture(CoachingExchangeFact)
    case develops(piece: Piece.Kind)
    case advancesCenterPawn
    case castles
    case addsDefender(piece: Piece.Kind)
    case createsThreat(piece: Piece.Kind)
    case centralizes(piece: Piece.Kind)
    case constructive(task: CoachingWakeTask, move: Move, piece: Piece.Kind)
    case verifiedSafe
}

enum CoachingCheckResolution: Equatable, Sendable {
    case movedKing
    case blocked(attacker: Piece.Kind, blocker: Piece.Kind)
    case capturedChecker(checker: Piece.Kind, capturer: Piece.Kind)
}

enum CoachingDangerResolution: Equatable, Sendable {
    case movedTarget(target: Piece.Kind, attacker: Piece.Kind)
    case capturedAttacker(
        capturer: Piece.Kind,
        target: Piece.Kind,
        attacker: Piece.Kind
    )
    case addedDefender(defender: Piece.Kind, target: Piece.Kind, attacker: Piece.Kind)
}

enum CoachingFeedback: Equatable, Sendable {
    case safePiece(piece: Piece.Kind)
    case lowerPriorityDanger(
        chosen: Piece.Kind,
        chosenLoss: Int,
        primary: Piece.Kind,
        primaryLoss: Int
    )
    case attackedButProtected(
        target: Piece.Kind,
        attacker: Piece.Kind,
        defender: Piece.Kind,
        noPieceNeedsHelp: Bool
    )
    case expectedLearnerPiece
    case notCheckingPiece(piece: Piece.Kind?)
    case notAttacker(piece: Piece.Kind, target: Piece.Kind)
    case expectedAttacker(target: Piece.Kind)
    case blockedWakePiece(piece: Piece.Kind, blocker: Piece.Kind)
    case notWakeCandidate(piece: Piece.Kind, purpose: CoachingWakePurpose)
    case notReplyIssue
    case correctAbsence(CoachingAbsenceKind)
    case missedExistingAnswer(CoachingAbsenceKind)
    case missedOpponentReply
    case missedOpponentIssue(CoachingOpponentReplyFact)
    case opponentIssue(CoachingOpponentReplyFact)
    case opponentReplyLooksSafe
    case noSafeCaptureForPiece
    case safeCaptureHint(piece: Piece.Kind)
    case unsafeCapture(CoachingExchangeFact)
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
    let primaryMessage: String
    let instruction: String?
    let observation: String?
    let hint: CoachingHint?
    let routine: [CoachingRoutineState]
    let actions: [CoachingActionPresentation]
    let boardTask: CoachingBoardTask
    let focus: CoachFocusPresentation
}

extension CoachingPresentation {
    init(
        primaryMessage: String,
        instruction: String?,
        hint: CoachingHint?,
        routine: [CoachingRoutineState],
        actions: [CoachingActionPresentation],
        boardTask: CoachingBoardTask,
        focus: CoachFocusPresentation
    ) {
        self.init(
            primaryMessage: primaryMessage,
            instruction: instruction,
            observation: nil,
            hint: hint,
            routine: routine,
            actions: actions,
            boardTask: boardTask,
            focus: focus
        )
    }
}

protocol CoachingExplaining: Sendable {
    func presentation(for context: CoachingPresentationContext) -> CoachingPresentation
}
