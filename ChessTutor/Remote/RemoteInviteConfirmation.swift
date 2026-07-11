import Foundation

struct RemoteInviteConfirmation: Equatable {
    let opponentName: String
    let localPlayerColor: PieceColor?
    let allowsColorChoice: Bool

    init(
        opponentName: String,
        localPlayerColor: PieceColor?,
        allowsColorChoice: Bool? = nil
    ) {
        self.opponentName = opponentName
        self.localPlayerColor = localPlayerColor
        self.allowsColorChoice = allowsColorChoice ?? (localPlayerColor == nil)
    }

    var title: String {
        "\(opponentName) wants to play"
    }

    var startButtonTitle: String {
        "Start"
    }

    var cancelButtonTitle: String {
        "Cancel"
    }

    var requiresColorChoice: Bool {
        allowsColorChoice && localPlayerColor == nil
    }

    var canStart: Bool {
        localPlayerColor != nil
    }

    var whitePlayerName: String {
        guard let localPlayerColor else {
            return "Choose White"
        }
        return localPlayerColor == .white ? "You" : opponentName
    }

    var blackPlayerName: String {
        guard let localPlayerColor else {
            return "Choose Black"
        }
        return localPlayerColor == .black ? "You" : opponentName
    }

    var whiteSeat: RemoteGameSeat {
        RemoteGameSeat(color: .white, playerName: whitePlayerName, squareTone: .dark)
    }

    var blackSeat: RemoteGameSeat {
        RemoteGameSeat(color: .black, playerName: blackPlayerName, squareTone: .light)
    }

    func selectColor(_ color: PieceColor) -> RemoteInviteConfirmation {
        guard allowsColorChoice else {
            return self
        }
        return RemoteInviteConfirmation(
            opponentName: opponentName,
            localPlayerColor: color,
            allowsColorChoice: true
        )
    }
}
