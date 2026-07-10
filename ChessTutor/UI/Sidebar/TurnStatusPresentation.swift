struct TurnStatusPresentation: Equatable {
    let headline: String
    let detail: String?

    init(session: GameSession, remoteOpponentName: String?) {
        self.headline = session.statusText

        if let guidanceText = session.guidanceText {
            self.detail = guidanceText
        } else if let remoteOpponentName {
            self.detail = session.localCanActForCurrentTurn
                ? "It's your move."
                : "Waiting for \(remoteOpponentName) to move."
        } else {
            self.detail = nil
        }
    }
}
