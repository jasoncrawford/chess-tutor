import Foundation

struct TurnStatusPresentation: Equatable {
    let headline: String
    let detail: String?

    init(
        session: GameSession,
        remoteOpponentName: String?,
        remotePresence: RemotePresenceUpdate? = nil,
        now: Date = Date()
    ) {
        self.headline = session.statusText

        if let guidanceText = session.guidanceText {
            self.detail = guidanceText
        } else if let remoteOpponentName {
            self.detail = Self.remoteDetail(
                opponentName: remoteOpponentName,
                remotePresence: remotePresence,
                localCanAct: session.localCanActForCurrentTurn,
                now: now
            )
        } else {
            self.detail = nil
        }
    }

    private static func remoteDetail(
        opponentName: String,
        remotePresence: RemotePresenceUpdate?,
        localCanAct: Bool,
        now: Date
    ) -> String {
        guard !localCanAct else {
            return "It's your move."
        }

        guard let remotePresence else {
            return "Waiting for \(opponentName) to move."
        }

        if remotePresence.expiresAt <= now {
            return "\(opponentName) is away from the board."
        }

        switch remotePresence.state {
        case .activeMoving:
            return "\(opponentName) is moving..."
        case .foregroundIdle:
            return "Waiting for \(opponentName) to move."
        case .away:
            return "\(opponentName) is away from the board."
        }
    }
}
