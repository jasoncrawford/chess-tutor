@testable import ChessTutor

actor ControllableCoachingAdvisor: CoachingAdvising {
    private var continuations: [Int: [CheckedContinuation<CoachingAdvice, any Error>]] = [:]

    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        try await withCheckedThrowingContinuation { continuation in
            continuations[request.positionRevision, default: []].append(continuation)
        }
    }

    func resolve(revision: Int, with advice: CoachingAdvice) {
        guard var queued = continuations[revision], !queued.isEmpty else { return }
        let continuation = queued.removeFirst()
        continuations[revision] = queued.isEmpty ? nil : queued
        continuation.resume(returning: advice)
    }

    func fail(revision: Int, with error: any Error = Failure()) {
        guard var queued = continuations[revision], !queued.isEmpty else { return }
        let continuation = queued.removeFirst()
        continuations[revision] = queued.isEmpty ? nil : queued
        continuation.resume(throwing: error)
    }

    func hasPending(revision: Int) -> Bool {
        !(continuations[revision] ?? []).isEmpty
    }

    struct Failure: Error, Sendable {}
}

struct ImmediateCoachingAdvisor: CoachingAdvising {
    let advice: CoachingAdvice

    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        advice.replacingRequest(with: request)
    }
}

extension CoachingAdvice {
    func replacingRequest(with request: CoachingRequest) -> CoachingAdvice {
        CoachingAdvice(
            evaluation: CoachingEvaluation(
                request: request,
                checkingPieces: evaluation.checkingPieces,
                opponentHasAnyLegalCapture: evaluation.opponentHasAnyLegalCapture,
                learnerHasAnyLegalCapture: evaluation.learnerHasAnyLegalCapture,
                opponentCaptureEstimates: evaluation.opponentCaptureEstimates,
                urgentProblems: evaluation.urgentProblems,
                learnerCaptureEstimates: evaluation.learnerCaptureEstimates,
                mateInOneMoves: evaluation.mateInOneMoves,
                moveAssessments: evaluation.moveAssessments
            ),
            insights: insights,
            urgentProblems: urgentProblems,
            takeOpportunities: takeOpportunities,
            wakeOpportunities: wakeOpportunities,
            moveAssessments: moveAssessments,
            openingDevelopmentIsRelevant: openingDevelopmentIsRelevant,
            confidence: confidence
        )
    }
}

extension CoachingSession {
    @discardableResult
    mutating func receive(_ advice: CoachingAdvice) -> [CoachingDirective] {
        let request = advice.evaluation.request
        return receive(
            advice,
            interaction: CoachingInteractionSnapshot(
                selectedSquare: request.tentativeMove?.to,
                tentativeMove: request.tentativeMove,
                positionRevision: request.positionRevision
            )
        )
    }
}

struct FailingCoachingAdvisor: CoachingAdvising {
    struct Failure: Error, Sendable {}

    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        throw Failure()
    }
}

struct CancellingCoachingAdvisor: CoachingAdvising {
    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        throw CancellationError()
    }
}

enum CoachingTestFixtures {
    static func state(
        sideToMove: PieceColor,
        pieces: [Square: Piece],
        castlingRights: CastlingRights = CastlingRights(),
        enPassantTarget: Square? = nil
    ) -> GameState {
        var pieces = pieces

        if !pieces.values.contains(where: { $0 == Piece(kind: .king, color: .white) }) {
            pieces[Square(file: .a, rank: 1)] = Piece(kind: .king, color: .white)
        }
        if !pieces.values.contains(where: { $0 == Piece(kind: .king, color: .black) }) {
            pieces[Square(file: .h, rank: 8)] = Piece(kind: .king, color: .black)
        }

        return GameState(
            board: Board(pieces: pieces),
            sideToMove: sideToMove,
            castlingRights: castlingRights,
            enPassantTarget: enPassantTarget
        )
    }

    static let whiteKing = Square(file: .e, rank: 1)
    static let blackKing = Square(file: .e, rank: 8)
    static let whiteQueen = Square(file: .d, rank: 4)
    static let whiteRook = Square(file: .f, rank: 4)
    static let blackBishop = Square(file: .b, rank: 8)
    static let blackRook = Square(file: .f, rank: 7)
    static let openingKnight = Square(file: .b, rank: 1)
    static let openingKnightMove = Move(
        from: openingKnight,
        to: Square(file: .c, rank: 3)
    )
    static let alternateKnight = Square(file: .g, rank: 1)
    static let alternateKnightMove = Move(
        from: alternateKnight,
        to: Square(file: .f, rank: 3)
    )
    static let safeMove = Move(
        from: whiteQueen,
        to: Square(file: .e, rank: 3)
    )
    static let profitableCapture = Move(
        from: whiteQueen,
        to: blackRook
    )
    static let fallbackMove = Move(
        from: Square(file: .a, rank: 2),
        to: Square(file: .a, rank: 3)
    )

    static let coachingState = state(
        sideToMove: .white,
        pieces: [
            whiteKing: Piece(kind: .king, color: .white),
            blackKing: Piece(kind: .king, color: .black),
            whiteQueen: Piece(kind: .queen, color: .white),
            whiteRook: Piece(kind: .rook, color: .white),
            openingKnight: Piece(kind: .knight, color: .white),
            alternateKnight: Piece(kind: .knight, color: .white),
            Square(file: .a, rank: 2): Piece(kind: .pawn, color: .white),
            blackBishop: Piece(kind: .bishop, color: .black),
            blackRook: Piece(kind: .rook, color: .black),
        ]
    )

    static let startingPositionAdvice = advice(
        state: .startingPosition(),
        opponentHasCapture: false,
        learnerHasCapture: false,
        wake: [
            opportunity(
                concept: .developsKnightOrBishop,
                subjects: [openingKnight],
                moves: [openingKnightMove],
                evidence: .development(
                    source: openingKnight,
                    destination: openingKnightMove.to
                )
            ),
            opportunity(
                concept: .developsKnightOrBishop,
                subjects: [alternateKnight],
                moves: [alternateKnightMove],
                evidence: .development(
                    source: alternateKnight,
                    destination: alternateKnightMove.to
                )
            ),
        ],
        assessments: [
            acceptableAssessment(
                openingKnightMove,
                concepts: [.developsKnightOrBishop]
            ),
            acceptableAssessment(
                alternateKnightMove,
                concepts: [.developsKnightOrBishop]
            ),
        ],
        opening: true
    )

    static let mixedPurposeWakeAdvice = advice(
        opponentHasCapture: false,
        learnerHasCapture: false,
        wake: [
            opportunity(
                concept: .developsKnightOrBishop,
                subjects: [openingKnight],
                moves: [openingKnightMove],
                evidence: .development(
                    source: openingKnight,
                    destination: openingKnightMove.to
                )
            ),
            opportunity(
                concept: .addsUsefulDefender,
                subjects: [whiteQueen],
                moves: [safeMove],
                evidence: .defender(source: whiteQueen, target: whiteRook)
            ),
        ],
        assessments: [
            acceptableAssessment(
                openingKnightMove,
                concepts: [.developsKnightOrBishop]
            ),
            acceptableAssessment(
                safeMove,
                concepts: [.addsUsefulDefender]
            ),
        ]
    )

    static let multipleDangerAdvice: CoachingAdvice = {
        let queenCapture = capture(
            move: Move(from: blackBishop, to: whiteQueen),
            captured: Piece(kind: .queen, color: .white),
            capturedSquare: whiteQueen,
            net: 9
        )
        let rookCapture = capture(
            move: Move(from: blackRook, to: whiteRook),
            captured: Piece(kind: .rook, color: .white),
            capturedSquare: whiteRook,
            net: 5
        )
        return advice(
            opponentHasCapture: true,
            learnerHasCapture: false,
            opponentCaptures: [queenCapture, rookCapture],
            urgent: [
                CoachingUrgentProblem(
                    target: whiteQueen,
                    piece: Piece(kind: .queen, color: .white),
                    captures: [queenCapture],
                    worstEstimatedLoss: 9
                ),
                CoachingUrgentProblem(
                    target: whiteRook,
                    piece: Piece(kind: .rook, color: .white),
                    captures: [rookCapture],
                    worstEstimatedLoss: 5
                ),
            ],
            assessments: [
                acceptableAssessment(
                    safeMove,
                    resolvesRequiredDanger: true,
                    concepts: [.pieceNeedsHelp]
                ),
            ]
        )
    }()

    static let nontrivialSafeClearAdvice = advice(
        opponentHasCapture: true,
        learnerHasCapture: false
    )

    static let takeAdvice: CoachingAdvice = {
        let estimate = capture(
            move: profitableCapture,
            captured: Piece(kind: .rook, color: .black),
            capturedSquare: blackRook,
            net: 5
        )
        return advice(
            opponentHasCapture: false,
            learnerHasCapture: true,
            learnerCaptures: [estimate],
            take: [opportunity(
                concept: .profitableCapture,
                subjects: [blackRook],
                moves: [profitableCapture],
                evidence: .capture(estimate)
            )],
            assessments: [acceptableAssessment(
                profitableCapture,
                concepts: [.profitableCapture]
            )]
        )
    }()

    static let nontrivialTakeClearAdvice = advice(
        opponentHasCapture: false,
        learnerHasCapture: true
    )

    static let fallbackAdvice = advice(
        opponentHasCapture: false,
        learnerHasCapture: false,
        assessments: [acceptableAssessment(fallbackMove)],
        confidence: .unsupported
    )

    static func adviceForTentativeMove(
        _ move: Move,
        origin: CoachingMoveOrigin,
        assessment: CoachingMoveAssessment,
        learnerCaptures: [CoachingCaptureEstimate] = [],
        urgent: [CoachingUrgentProblem] = [],
        confidence: CoachingConfidence = .high
    ) -> CoachingAdvice {
        advice(
            tentativeMove: move,
            context: .tentativeMove(origin: origin),
            opponentHasCapture: false,
            learnerHasCapture: !learnerCaptures.isEmpty,
            learnerCaptures: learnerCaptures,
            urgent: urgent,
            assessments: [assessment],
            confidence: confidence
        )
    }

    static func acceptableAssessment(
        _ move: Move,
        resolvesRequiredDanger: Bool = true,
        issues: [CoachingOpponentIssue] = [],
        concepts: [CoachingConcept] = [],
        isAcceptable: Bool = true
    ) -> CoachingMoveAssessment {
        CoachingMoveAssessment(
            move: move,
            isLegal: true,
            resolvesRequiredDanger: resolvesRequiredDanger,
            opponentIssues: issues,
            concepts: concepts,
            isAcceptable: isAcceptable
        )
    }

    static func issue(
        reply: Move,
        kind: CoachingOpponentIssueKind,
        severity: CoachingOpponentIssueSeverity,
        answers: Set<Square>
    ) -> CoachingOpponentIssue {
        CoachingOpponentIssue(
            reply: reply,
            kind: kind,
            severity: severity,
            answerSquares: answers
        )
    }

    static func capture(
        move: Move,
        captured: Piece,
        capturedSquare: Square,
        recapture: Move? = nil,
        net: Int
    ) -> CoachingCaptureEstimate {
        CoachingCaptureEstimate(
            move: move,
            capturedPiece: captured,
            capturedSquare: capturedSquare,
            immediateRecapture: recapture,
            netGainForMover: net
        )
    }

    static func opportunity(
        concept: CoachingConcept,
        subjects: Set<Square>,
        moves: [Move],
        evidence: CoachingEvidence
    ) -> CoachingOpportunity {
        CoachingOpportunity(
            concept: concept,
            subjectSquares: subjects,
            moves: moves,
            priority: 1,
            evidence: evidence
        )
    }

    static func advice(
        state: GameState = coachingState,
        tentativeMove: Move? = nil,
        context: CoachingRequest.Context = .start,
        learner: PieceColor = .white,
        checking: Set<Square> = [],
        opponentHasCapture: Bool,
        learnerHasCapture: Bool,
        opponentCaptures: [CoachingCaptureEstimate] = [],
        learnerCaptures: [CoachingCaptureEstimate] = [],
        mateInOne: Set<Move> = [],
        urgent: [CoachingUrgentProblem] = [],
        take: [CoachingOpportunity] = [],
        wake: [CoachingOpportunity] = [],
        assessments: [CoachingMoveAssessment] = [],
        opening: Bool = false,
        confidence: CoachingConfidence = .high
    ) -> CoachingAdvice {
        let request = CoachingRequest(
            committedState: state,
            tentativeMove: tentativeMove,
            learner: learner,
            positionRevision: 7,
            context: context
        )
        let assessmentMap = Dictionary(
            uniqueKeysWithValues: assessments.map { ($0.move, $0) }
        )
        let evaluation = CoachingEvaluation(
            request: request,
            checkingPieces: checking,
            opponentHasAnyLegalCapture: opponentHasCapture,
            learnerHasAnyLegalCapture: learnerHasCapture,
            opponentCaptureEstimates: opponentCaptures,
            urgentProblems: urgent,
            learnerCaptureEstimates: learnerCaptures,
            mateInOneMoves: mateInOne,
            moveAssessments: assessmentMap
        )
        return CoachingAdvice(
            evaluation: evaluation,
            insights: [],
            urgentProblems: urgent,
            takeOpportunities: take,
            wakeOpportunities: wake,
            moveAssessments: assessmentMap,
            openingDevelopmentIsRelevant: opening,
            confidence: confidence
        )
    }
}
