enum RemoteMoveLog {
    struct ApplyResult: Equatable {
        let state: GameState
        let lastAppliedSequence: Int
    }

    enum Error: Swift.Error, Equatable {
        case wrongGame(expected: RemoteGameID, actual: RemoteGameID)
        case unsupportedProtocolVersion(Int)
        case unexpectedSequence(expected: Int, actual: Int)
        case wrongActor(expected: RemotePlayerID, actual: RemotePlayerID)
        case previousFingerprintMismatch
        case resultingFingerprintMismatch
        case illegalMove(Move)
    }

    static func apply(
        events: [RemoteMoveEvent],
        to initialState: GameState,
        gameID: RemoteGameID,
        protocolVersion: Int,
        whitePlayerID: RemotePlayerID,
        blackPlayerID: RemotePlayerID,
        startingAfter lastAppliedSequence: Int = 0
    ) throws -> ApplyResult {
        var state = initialState
        var expectedSequence = lastAppliedSequence + 1

        for event in events.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            guard event.gameID == gameID else {
                throw Error.wrongGame(expected: gameID, actual: event.gameID)
            }

            guard event.protocolVersion == protocolVersion else {
                throw Error.unsupportedProtocolVersion(event.protocolVersion)
            }

            guard event.sequenceNumber == expectedSequence else {
                throw Error.unexpectedSequence(expected: expectedSequence, actual: event.sequenceNumber)
            }

            let expectedActor = state.sideToMove == .white ? whitePlayerID : blackPlayerID
            guard event.actorPlayerID == expectedActor else {
                throw Error.wrongActor(expected: expectedActor, actual: event.actorPlayerID)
            }

            guard event.previousPositionFingerprint == PositionFingerprinting.fingerprint(for: state) else {
                throw Error.previousFingerprintMismatch
            }

            let move = try RemoteMoveCodec.decode(event.move)
            guard LegalMoveGenerator.allLegalMoves(in: state).contains(move) else {
                throw Error.illegalMove(move)
            }

            state.apply(move)

            guard event.resultingPositionFingerprint == PositionFingerprinting.fingerprint(for: state) else {
                throw Error.resultingFingerprintMismatch
            }

            expectedSequence += 1
        }

        return ApplyResult(state: state, lastAppliedSequence: expectedSequence - 1)
    }
}
