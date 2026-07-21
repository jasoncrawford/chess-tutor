enum PlayerSeat: Equatable, Sendable {
    case humanLocal
    case remote(playerID: String)

    var isLocal: Bool {
        self == .humanLocal
    }
}
