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

    struct PendingJoinRequest: Equatable, Hashable {
        let invite: PendingInvite
        let joinerDisplayName: String
    }

    struct OutgoingJoinRequest: Equatable, Hashable {
        let code: String
        let inviterDisplayName: String
    }

    enum Stage: Equatable, Hashable {
        case closed
        case choosing
        case choosingWhite(InviteTarget)
        case waitingForInvitee(PendingInvite)
        case reviewingJoinRequest(PendingJoinRequest)
        case waitingForInviterApproval(OutgoingJoinRequest)
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

        let outgoingJoinRequest = OutgoingJoinRequest(
            code: joinCode,
            inviterDisplayName: "the inviter"
        )
        joinCode = ""
        joinErrorMessage = nil
        stage = .waitingForInviterApproval(outgoingJoinRequest)
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

    @discardableResult
    func receiveJoinRequest(displayName: String) -> PendingJoinRequest {
        let pendingInvite: PendingInvite
        if case .waitingForInvitee(let invite) = stage {
            pendingInvite = invite
        } else {
            pendingInvite = PendingInvite(
                target: .newPlayer,
                whiteChoice: selectedWhiteChoice,
                code: nextInviteCode
            )
        }

        let pendingJoinRequest = PendingJoinRequest(
            invite: pendingInvite,
            joinerDisplayName: displayName
        )
        stage = .reviewingJoinRequest(pendingJoinRequest)
        return pendingJoinRequest
    }

    @discardableResult
    func approveJoinRequest() -> PendingJoinRequest? {
        guard case .reviewingJoinRequest(let pendingJoinRequest) = stage else {
            return nil
        }

        stage = .closed
        return pendingJoinRequest
    }

    func declineJoinRequest() {
        guard case .reviewingJoinRequest(let pendingJoinRequest) = stage else {
            return
        }

        stage = .waitingForInvitee(pendingJoinRequest.invite)
    }

    func goBack() {
        switch stage {
        case .choosingWhite, .waitingForInvitee:
            selectedWhiteChoice = .localPlayer
            stage = .choosing
        case .closed, .choosing, .reviewingJoinRequest, .waitingForInviterApproval:
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
