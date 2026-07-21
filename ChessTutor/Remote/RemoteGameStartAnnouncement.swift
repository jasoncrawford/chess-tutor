import Foundation

enum RemoteGameSeatSquareTone: Equatable {
    case light
    case dark
}

struct RemoteGameSeat: Equatable {
    let color: PieceColor
    let playerName: String
    let squareTone: RemoteGameSeatSquareTone
}

struct RemoteGameStartAnnouncement: Equatable {
    let opponentName: String
    let localPlayerColor: PieceColor

    var title: String {
        "You're playing \(opponentName)"
    }

    var whitePlayerName: String {
        localPlayerColor == .white ? "You" : opponentName
    }

    var blackPlayerName: String {
        localPlayerColor == .black ? "You" : opponentName
    }

    var whiteSeat: RemoteGameSeat {
        RemoteGameSeat(color: .white, playerName: whitePlayerName, squareTone: .dark)
    }

    var blackSeat: RemoteGameSeat {
        RemoteGameSeat(color: .black, playerName: blackPlayerName, squareTone: .light)
    }

    var buttonTitle: String {
        "Start"
    }
}
