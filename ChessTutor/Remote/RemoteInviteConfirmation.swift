import Foundation

enum RemoteInviteConfirmationPurpose: String, Equatable {
    case play
    case newGame
}

struct RemoteInviteConfirmation: Equatable {
    let opponentName: String
    let localPlayerColor: PieceColor?
    let allowsColorChoice: Bool
    let purpose: RemoteInviteConfirmationPurpose
    private let terminalTitle: String?

    init(
        opponentName: String,
        localPlayerColor: PieceColor?,
        allowsColorChoice: Bool? = nil,
        purpose: RemoteInviteConfirmationPurpose = .play,
        terminalTitle: String? = nil
    ) {
        self.opponentName = opponentName
        self.localPlayerColor = localPlayerColor
        self.allowsColorChoice = allowsColorChoice ?? (localPlayerColor == nil)
        self.purpose = purpose
        self.terminalTitle = terminalTitle
    }

    static func terminal(title: String) -> RemoteInviteConfirmation {
        RemoteInviteConfirmation(
            opponentName: "",
            localPlayerColor: nil,
            allowsColorChoice: false,
            terminalTitle: title
        )
    }

    var title: String {
        if let terminalTitle {
            return terminalTitle
        }

        switch purpose {
        case .play:
            return "\(opponentName) wants to play"
        case .newGame:
            return "\(opponentName) wants to start a new game"
        }
    }

    var startButtonTitle: String {
        "Start"
    }

    var cancelButtonTitle: String {
        "Cancel"
    }

    var acknowledgementButtonTitle: String {
        "OK"
    }

    var isTerminal: Bool {
        terminalTitle != nil
    }

    var showsColorSeats: Bool {
        !isTerminal
    }

    var requiresColorChoice: Bool {
        !isTerminal && allowsColorChoice && localPlayerColor == nil
    }

    var canStart: Bool {
        !isTerminal && localPlayerColor != nil
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
        guard !isTerminal, allowsColorChoice else {
            return self
        }
        return RemoteInviteConfirmation(
            opponentName: opponentName,
            localPlayerColor: color,
            allowsColorChoice: true,
            purpose: purpose
        )
    }
}
