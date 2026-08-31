struct HostedCoachingPresentationProjector: Sendable {
    func presentation(
        for phase: HostedCoachingPhase,
        pulseID: Int
    ) -> CoachingPresentation {
        switch phase {
        case .thinking:
            return makePresentation(
                message: "Thinking…",
                actions: [closeAction],
                focus: .empty
            )
        case .failed:
            return makePresentation(
                message: "I couldn't get help right now.",
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
                actions: turn.actions.compactMap(actionPresentation) + [closeAction],
                focus: focusPresentation(for: turn.focus, pulseID: pulseID)
            )
        }
    }

    private func makePresentation(
        message: String,
        actions: [CoachingActionPresentation],
        focus: CoachFocusPresentation
    ) -> CoachingPresentation {
        CoachingPresentation(
            primaryMessage: message,
            instruction: nil,
            observation: nil,
            hint: nil,
            routine: [],
            actions: actions,
            boardTask: .none,
            focus: focus
        )
    }

    private func actionPresentation(_ action: String) -> CoachingActionPresentation? {
        switch action {
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
