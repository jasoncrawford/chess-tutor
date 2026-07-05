import Observation

struct KnownRemotePlayer: Equatable, Hashable, Identifiable, Sendable {
    let id: RemotePlayerID
    let displayName: String
}

@Observable
final class RemotePlayFlow {
    enum InviteTarget: Equatable, Hashable {
        case known(KnownRemotePlayer)
        case newPlayer
    }

    enum WhiteChoice: Equatable, Hashable {
        case localPlayer
        case invitee
        case inviteeChooses
    }

    struct PendingInvite: Equatable, Hashable {
        let target: InviteTarget
        let whiteChoice: WhiteChoice
        let code: String

        var formattedCode: String {
            guard code.count == 6 else {
                return code
            }
            let splitIndex = code.index(code.startIndex, offsetBy: 3)
            return "\(code[..<splitIndex]) \(code[splitIndex...])"
        }
    }

    enum Stage: Equatable, Hashable {
        case closed
        case choosing
        case choosingWhite(InviteTarget)
        case waitingForInvitee(PendingInvite)
    }

    private let nextInviteCode: String
    private(set) var knownPlayers: [KnownRemotePlayer]
    private(set) var stage: Stage = .closed
    var selectedWhiteChoice: WhiteChoice = .localPlayer

    init(knownPlayers: [KnownRemotePlayer] = [], nextInviteCode: String = "428193") {
        self.knownPlayers = knownPlayers
        self.nextInviteCode = nextInviteCode
    }

    func canShowEntryPoint(for session: GameSession) -> Bool {
        session.state.result == .ongoing
            && !session.hasGameInProgress
            && session.whitePlayer == .humanLocal
            && session.blackPlayer == .humanLocal
    }

    func open() {
        selectedWhiteChoice = .localPlayer
        stage = .choosing
    }

    func invite(_ player: KnownRemotePlayer) {
        selectedWhiteChoice = .localPlayer
        stage = .choosingWhite(.known(player))
    }

    func inviteSomeoneNew() {
        selectedWhiteChoice = .localPlayer
        stage = .choosingWhite(.newPlayer)
    }

    func chooseWhite(_ choice: WhiteChoice) {
        selectedWhiteChoice = choice
    }

    @discardableResult
    func sendInvite() -> PendingInvite {
        let target: InviteTarget
        if case .choosingWhite(let selectedTarget) = stage {
            target = selectedTarget
        } else {
            target = .newPlayer
        }

        let pendingInvite = PendingInvite(
            target: target,
            whiteChoice: selectedWhiteChoice,
            code: nextInviteCode
        )
        stage = .waitingForInvitee(pendingInvite)
        return pendingInvite
    }

    func cancel() {
        selectedWhiteChoice = .localPlayer
        stage = .closed
    }
}
