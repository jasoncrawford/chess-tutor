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
        NewGameConfirmationPresentation(
            title: "Start a new game?",
            message: "You can invite \(opponentName) again or start a new game here.",
            cancelActionTitle: "Keep Playing",
            remoteInviteActionTitle: "Invite \(opponentName) Again",
            localResetActionTitle: "New Game Here"
        )
    }
}

enum NewGameRequestPolicy {
    static func shouldConfirm(hasGameInProgress: Bool, isRemoteGameActive: Bool) -> Bool {
        hasGameInProgress || isRemoteGameActive
    }
}
