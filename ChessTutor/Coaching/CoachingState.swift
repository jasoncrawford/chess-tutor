enum CoachingStage: Equatable, Sendable {
    case awaitingAdvice(origin: CoachingMoveOrigin?)
    case checkLocate
    case checkResolve
    case safeLocate
    case safeIdentifyAttacker(target: Square)
    case safeResolve(target: Square)
    case takeChooseMove
    case wakeChoosePiece(purpose: CoachingWakePurpose)
    case wakeChooseMove(piece: Square, purpose: CoachingWakePurpose)
    case fallbackChooseMove
    case opponentCheck(move: Move, origin: CoachingMoveOrigin)
    case reviseMove(origin: CoachingMoveOrigin)
    case complete(move: Move, origin: CoachingMoveOrigin, concepts: [CoachingConcept])
}

enum CoachingEvent: Equatable, Sendable {
    case identificationTapped(Square)
    case interactionChanged(CoachingInteractionSnapshot)
    case actionChosen(CoachingAction)
}

enum CoachingDirective: Equatable, Sendable {
    case requestAdvice(context: CoachingRequest.Context)
    case discardTentativeMove
    case stop(preservingTentativeMove: Bool)
    case commitWithExistingDonePath
}

struct CoachingInteractionSnapshot: Equatable, Sendable {
    let selectedSquare: Square?
    let tentativeMove: Move?
    let positionRevision: Int
}

enum CoachingQuestionID: Equatable, Sendable {
    case checkLocate
    case checkResolve(checker: Square)
    case safeLocate
    case safeAttacker(target: Square)
    case safeResolve(target: Square, attacker: Square)
    case take
    case wakeSource(purpose: CoachingWakePurpose)
    case wakeMove(source: Square, purpose: CoachingWakePurpose)
    case fallback
    case opponentReply(move: Move, origin: CoachingMoveOrigin)
    case revise(move: Move?, origin: CoachingMoveOrigin)
    case complete(move: Move, origin: CoachingMoveOrigin)
}

enum CoachingReplyAnswer: Equatable, Sendable {
    case looksSafe(move: Move)
    case issue(move: Move, issue: CoachingOpponentIssue)
}

struct CoachingPedagogicalEvidence: Equatable, Sendable {
    var checkingPiece: Square?
    var safeTarget: Square?
    var safeAttacker: Square?
    var confirmedSafeAbsence: Bool
    var confirmedTakeAbsence: Bool
    var tentativeOrigin: CoachingMoveOrigin?
    var replyAnswer: CoachingReplyAnswer?

    static let empty = CoachingPedagogicalEvidence(
        checkingPiece: nil,
        safeTarget: nil,
        safeAttacker: nil,
        confirmedSafeAbsence: false,
        confirmedTakeAbsence: false,
        tentativeOrigin: nil,
        replyAnswer: nil
    )
}

struct CoachingKnowledge: Equatable, Sendable {
    var positionAdvice: CoachingAdvice?
    var tentativeAdvice: CoachingAdvice?
    var unsupportedContext: CoachingRequest.Context?
    var pendingContext: CoachingRequest.Context?
}

struct CoachingQuestionProgress: Equatable, Sendable {
    var questionID: CoachingQuestionID?
    var hintLevel: Int
    var missesAtCurrentLevel: Int
    var feedback: CoachingFeedback?
    var feedbackAnchor: CoachingFeedbackAnchor?
    var pulseID: Int
}

enum CoachingFeedbackAnchor: Equatable, Sendable {
    case identification(square: Square)
    case selection(square: Square?)
    case tentativeMove(Move)
    case action(CoachingAction)
}

struct CoachingEpisodeState: Equatable, Sendable {
    var knowledge: CoachingKnowledge
    var evidence: CoachingPedagogicalEvidence
    var progress: CoachingQuestionProgress
    var interaction: CoachingInteractionSnapshot
}

struct CoachingDerivedState: Equatable, Sendable {
    let stage: CoachingStage
    let questionID: CoachingQuestionID?
    let promptOverride: CoachingPrompt?
    let derivedFeedback: CoachingFeedback?
    let requestedAdvice: CoachingRequest.Context?
}
