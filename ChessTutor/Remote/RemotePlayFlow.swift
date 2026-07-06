import Observation

struct KnownRemotePlayer: Codable, Equatable, Hashable, Identifiable, Sendable {
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
    private(set) var joinCode = ""
    private(set) var joinErrorMessage: String?

    var canSubmitJoinCode: Bool {
        joinCode.count == 6
    }

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
        joinErrorMessage = nil
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

    func rememberKnownPlayer(_ player: KnownRemotePlayer) {
        if let existingIndex = knownPlayers.firstIndex(where: { $0.id == player.id }) {
            knownPlayers[existingIndex] = player
        } else {
            knownPlayers.append(player)
        }
        knownPlayers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func updateJoinCode(_ code: String) {
        joinCode = String(code.filter(\.isNumber).prefix(6))
        joinErrorMessage = nil
    }

    @discardableResult
    func acceptJoinCode() -> Bool {
        guard canSubmitJoinCode, joinCode == nextInviteCode else {
            joinErrorMessage = "That code did not match an open invite."
            return false
        }

        joinCode = ""
        joinErrorMessage = nil
        stage = .closed
        return true
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

    func goBack() {
        switch stage {
        case .choosingWhite, .waitingForInvitee:
            selectedWhiteChoice = .localPlayer
            stage = .choosing
        case .closed, .choosing:
            break
        }
    }

    func cancel() {
        selectedWhiteChoice = .localPlayer
        joinCode = ""
        joinErrorMessage = nil
        stage = .closed
    }
}
