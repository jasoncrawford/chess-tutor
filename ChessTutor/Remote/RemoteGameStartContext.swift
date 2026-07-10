struct RemoteGameStartContext: Equatable {
    let descriptor: RemoteGameDescriptor
    let opponent: RemotePlayerRef
    let localPlayerColor: PieceColor

    static func joiner(from acceptedInvite: RemoteAcceptedInvite) -> RemoteGameStartContext {
        make(
            acceptedInvite: acceptedInvite,
            localPlayer: acceptedInvite.joiner,
            opponent: acceptedInvite.invite.inviter,
            localPlayerColor: acceptedInvite.joinerColor
        )
    }

    static func inviter(from acceptedInvite: RemoteAcceptedInvite) -> RemoteGameStartContext {
        make(
            acceptedInvite: acceptedInvite,
            localPlayer: acceptedInvite.invite.inviter,
            opponent: acceptedInvite.joiner,
            localPlayerColor: acceptedInvite.joinerColor.opposite
        )
    }

    private static func make(
        acceptedInvite: RemoteAcceptedInvite,
        localPlayer: RemotePlayerRef,
        opponent: RemotePlayerRef,
        localPlayerColor: PieceColor
    ) -> RemoteGameStartContext {
        let whitePlayer: RemotePlayerRef
        let blackPlayer: RemotePlayerRef
        switch acceptedInvite.joinerColor {
        case .white:
            whitePlayer = acceptedInvite.joiner
            blackPlayer = acceptedInvite.invite.inviter
        case .black:
            whitePlayer = acceptedInvite.invite.inviter
            blackPlayer = acceptedInvite.joiner
        }

        return RemoteGameStartContext(
            descriptor: RemoteGameDescriptor(
                id: RemoteGameID(rawValue: acceptedInvite.invite.id.rawValue),
                protocolVersion: acceptedInvite.invite.protocolVersion,
                status: .active,
                whitePlayer: whitePlayer,
                blackPlayer: blackPlayer,
                localPlayerID: localPlayer.id
            ),
            opponent: opponent,
            localPlayerColor: localPlayerColor
        )
    }
}
