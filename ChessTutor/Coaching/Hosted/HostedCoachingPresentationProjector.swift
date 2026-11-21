struct HostedCoachingPresentationProjector: Sendable {
    func presentation(for session: HostedCoachingSession, board: Board, tentativeMove: Move?) -> CoachingPresentation {
        if session.isPlayingInstead {
            return makePresentation(message: "Try a move on the board.", actions: [closeAction], focus: .empty, boardTask: .move)
        }
        let waitingForAnswer = session.phase == .thinking && session.isAnswering
        let phase = waitingForAnswer ? session.displayedTurn.map(HostedCoachingPhase.ready) ?? session.phase : session.phase
        var result = presentation(for: phase, pulseID: session.pulseID)
        result.canPlayInstead = session.isAnswering
        result.isAwaitingAnswer = waitingForAnswer
        guard case .ready(let turn) = phase else { return result }
        result.visualContent = turn.visualContent
        result.canReplayVisual = !waitingForAnswer && turn.visualContent?.visuals.isEmpty == false
        var emphasized = Set<Square>()
        var candidates = Set<Square>()
        var paths = Set<CoachFocusPath>()
        if let answer = session.answerSquare {
            emphasized.insert(answer)
        } else if let reference = session.referenceSquare.flatMap(square) {
            emphasized.insert(reference)
        } else if let content = turn.visualContent {
            for cue in content.visuals {
                guard let from = square(cue.endpoints.from), let to = square(cue.endpoints.to) else { continue }
                switch cue {
                case .attack:
                    paths.insert(.init(source: from, destination: to, role: .attacker))
                case .move:
                    let revision = tentativeMove?.from == from && tentativeMove?.to != to
                    let source = revision ? tentativeMove!.to : from
                    let knight = board[from]?.kind == .knight
                    paths.insert(.init(source: source, destination: to, role: .candidate,
                        geometryKind: revision ? .relocation : knight ? .knight : .direct))
                }
                candidates.insert(to)
            }
        }
        if turn.visualContent != nil || session.answerSquare != nil {
            result.focus = .init(emphasizedSquares: emphasized, candidateSquares: candidates,
                                paths: paths, pulseID: session.pulseID)
        }
        return result
    }

    func presentation(
        for phase: HostedCoachingPhase,
        pulseID: Int
    ) -> CoachingPresentation {
        switch phase {
        case .thinking:
            return makePresentation(
                message: "Thinking…",
                actions: [closeAction],
                focus: .empty,
                isThinking: true
            )
        case .failed, .timedOut:
            return makePresentation(
                message: phase == .timedOut
                    ? "The coach took too long to reply. Try again, or keep playing."
                    : "I couldn't get help right now.",
                actions: [
                    CoachingActionPresentation(
                        action: .hint,
                        title: "Try again",
                        accessibilityLabel: "Try coaching again",
                        prominence: .primary
                    ),
                    closeAction,
                ],
                focus: .empty
            )
        case .ready(let turn):
            return makePresentation(
                message: turn.message,
                actions: responseActions(for: turn.expects)
                    + turn.actions.compactMap(actionPresentation)
                    + [closeAction],
                focus: focusPresentation(for: turn.focus, pulseID: pulseID),
                boardTask: boardTask(for: turn.expects)
            )
        }
    }

    private func makePresentation(
        message: String,
        actions: [CoachingActionPresentation],
        focus: CoachFocusPresentation,
        boardTask: CoachingBoardTask = .none,
        isThinking: Bool = false
    ) -> CoachingPresentation {
        CoachingPresentation(
            primaryMessage: message,
            instruction: nil,
            observation: nil,
            hint: nil,
            routine: [],
            actions: actions,
            boardTask: boardTask,
            focus: focus,
            isThinking: isThinking
        )
    }

    private func actionPresentation(_ action: String) -> CoachingActionPresentation? {
        switch action {
        case "noPieceNeedsHelp":
            return CoachingActionPresentation(
                action: .noAnswer,
                title: "No piece needs help",
                accessibilityLabel: "No piece needs help",
                prominence: .secondary
            )
        case "noSafeCapture":
            return CoachingActionPresentation(
                action: .noAnswer,
                title: "No safe capture",
                accessibilityLabel: "No safe capture",
                prominence: .secondary
            )
        case "looksSafe":
            return CoachingActionPresentation(
                action: .looksSafe,
                title: "Looks safe",
                accessibilityLabel: "The move looks safe",
                prominence: .secondary
            )
        case "hint":
            return CoachingActionPresentation(
                action: .hint,
                title: "Hint",
                accessibilityLabel: "Show a hint",
                prominence: .secondary
            )
        case "playMove":
            return CoachingActionPresentation(
                action: .done,
                title: "Play this move",
                accessibilityLabel: "Play this move",
                prominence: .primary
            )
        case "tryAnotherMove":
            return CoachingActionPresentation(
                action: .keepLooking,
                title: "Try another move",
                accessibilityLabel: "Try another move",
                prominence: .secondary
            )
        default:
            return nil
        }
    }

    private func responseActions(
        for expectedResponse: ModelCoachingChessNativeExpectedResponse
    ) -> [CoachingActionPresentation] {
        switch expectedResponse {
        case .findEndangeredPiece:
            return [
                CoachingActionPresentation(
                    action: .noAnswer,
                    title: "No piece needs help",
                    accessibilityLabel: "No piece needs help",
                    prominence: .secondary
                ),
            ]
        case .findSafeCapture:
            return [
                CoachingActionPresentation(
                    action: .noAnswer,
                    title: "No safe capture",
                    accessibilityLabel: "No safe capture",
                    prominence: .secondary
                ),
            ]
        case .judgeMoveSafety:
            return [
                CoachingActionPresentation(
                    action: .looksSafe,
                    title: "Looks safe",
                    accessibilityLabel: "The move looks safe",
                    prominence: .secondary
                ),
                CoachingActionPresentation(
                    action: .keepLooking,
                    title: "Try another move",
                    accessibilityLabel: "Try another move",
                    prominence: .secondary
                ),
            ]
        case .chooseWhetherToPlay:
            return [
                CoachingActionPresentation(
                    action: .done,
                    title: "Play this move",
                    accessibilityLabel: "Play this move",
                    prominence: .primary
                ),
                CoachingActionPresentation(
                    action: .keepLooking,
                    title: "Try another move",
                    accessibilityLabel: "Try another move",
                    prominence: .secondary
                ),
            ]
        case .none, .selectPiece, .stageMove:
            return []
        }
    }

    private func boardTask(
        for expectedResponse: ModelCoachingChessNativeExpectedResponse
    ) -> CoachingBoardTask {
        switch expectedResponse {
        case .none, .judgeMoveSafety, .chooseWhetherToPlay:
            return .none
        case .selectPiece, .findEndangeredPiece, .findSafeCapture:
            return .identify(allowsMoveRevision: false)
        case .stageMove:
            return .move
        }
    }

    private var closeAction: CoachingActionPresentation {
        CoachingActionPresentation(
            action: .stop,
            title: "Close help",
            accessibilityLabel: "Close coaching help",
            prominence: .quiet
        )
    }

    private func focusPresentation(
        for focus: [ModelCoachingChessNativeFocus],
        pulseID: Int
    ) -> CoachFocusPresentation {
        var emphasizedSquares = Set<Square>()
        var candidateSquares = Set<Square>()
        var paths = Set<CoachFocusPath>()
        for item in focus {
            switch item {
            case .square(let value):
                if let square = square(value) {
                    emphasizedSquares.insert(square)
                }
            case .move(let from, let to):
                guard let source = square(from), let destination = square(to) else {
                    continue
                }
                candidateSquares.insert(destination)
                paths.insert(
                    CoachFocusPath(
                        source: source,
                        destination: destination,
                        role: .candidate
                    )
                )
            }
        }
        return CoachFocusPresentation(
            emphasizedSquares: emphasizedSquares,
            candidateSquares: candidateSquares,
            paths: paths,
            pulseID: pulseID
        )
    }

    private func square(_ value: String) -> Square? {
        guard value.count == 2,
              let fileCharacter = value.first,
              let rankCharacter = value.last,
              let file = Square.File.allCases.first(where: {
                  String(UnicodeScalar(96 + $0.rawValue)!) == String(fileCharacter)
              }),
              let rank = Int(String(rankCharacter)),
              (1...8).contains(rank) else {
            return nil
        }
        return Square(file: file, rank: rank)
    }
}
