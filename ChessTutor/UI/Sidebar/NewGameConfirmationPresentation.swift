struct NewGameConfirmationPresentation: Equatable {
    let title: String
    let message: String
    let cancelActionTitle: String
    let remoteInviteActionTitle: String?
    let localResetActionTitle: String

    static let localGame = NewGameConfirmationPresentation(
        title: "Start a new game?",
        message: "This will abandon the current game.",
        cancelActionTitle: "Keep Playing",
        remoteInviteActionTitle: nil,
        localResetActionTitle: "New Game"
    )

    static let completedGame = NewGameConfirmationPresentation(
        title: "Start a new game?",
        message: "The board will be reset.",
        cancelActionTitle: "Keep Board",
        remoteInviteActionTitle: nil,
        localResetActionTitle: "New Game"
    )

    static func remoteGame(opponentName: String) -> NewGameConfirmationPresentation {
        remoteGame(opponentName: opponentName, cancelActionTitle: "Keep Playing")
    }

    private static func remoteGame(
        opponentName: String,
        cancelActionTitle: String
    ) -> NewGameConfirmationPresentation {
        NewGameConfirmationPresentation(
            title: "Start a new game?",
            message: "You can invite \(opponentName) again or start a new game here.",
            cancelActionTitle: cancelActionTitle,
            remoteInviteActionTitle: "Invite \(opponentName) Again",
            localResetActionTitle: "New Game Here"
        )
    }

    static func presentation(
        result: GameResult,
        isRemoteGameEnded: Bool,
        remoteOpponentName: String?
    ) -> NewGameConfirmationPresentation {
        if let remoteOpponentName, !isRemoteGameEnded {
            return remoteGame(
                opponentName: remoteOpponentName,
                cancelActionTitle: result == .ongoing ? "Keep Playing" : "Keep Board"
            )
        }

        guard result == .ongoing, !isRemoteGameEnded else {
            return .completedGame
        }
        return .localGame
    }
}

enum NewGameRequestPolicy {
    static func shouldConfirm(
        hasGameInProgress: Bool,
        isRemoteGameActive: Bool,
        gameResult: GameResult
    ) -> Bool {
        guard gameResult == .ongoing else {
            return false
        }
        return hasGameInProgress || isRemoteGameActive
    }
}

enum RemoteGameEndPublishingPolicy {
    static func shouldPublishOnLocalReset(result: GameResult) -> Bool {
        result == .ongoing
    }
}
