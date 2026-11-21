import Foundation

enum ModelCoachingVisualTurnDecoder {
    private struct WireTurn: Decodable {
        let message: [ModelCoachingVisualMessageRun]
        let actions: [String]
        let visuals: [ModelCoachingVisualCue]
        let expects: ModelCoachingChessNativeExpectedResponse
    }

    static func decodeAndValidate(
        _ data: Data,
        request: ModelCoachingNeutralRequest
    ) throws -> ModelCoachingChessNativeTurn {
        var rawValidator = ModelCoachingRawJSONValidator(data: data)
        try rawValidator.validate()
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys) == ["message", "actions", "visuals", "expects"],
              let rawRuns = raw["message"] as? [[String: Any]],
              let rawCues = raw["visuals"] as? [[String: Any]] else { throw invalid }
        for run in rawRuns {
            let keys: Set<String> = run["type"] as? String == "text"
                ? ["type", "text"] : ["type", "text", "square"]
            guard Set(run.keys) == keys else { throw invalid }
        }
        guard rawCues.allSatisfy({ Set($0.keys) == ["type", "from", "to"] }) else { throw invalid }

        let wire = try JSONDecoder().decode(WireTurn.self, from: data)
        let content = ModelCoachingVisualContent(runs: wire.message, visuals: wire.visuals)
        let turn = ModelCoachingChessNativeTurn(message: content.plainText, actions: wire.actions,
            focus: [], expects: wire.expects, visualContent: content)
        let legacyIssues = ModelCoachingChessNativeTurnValidator.issues(for: turn,
            contract: .init(availableActions: ["hint"], availableMoveFocus: []))
        guard legacyIssues.isEmpty, (1...9).contains(content.runs.count), content.visuals.count <= 1,
              wire.actions.count <= 1,
              [.findEndangeredPiece, .findSafeCapture, .stageMove, .judgeMoveSafety, .chooseWhetherToPlay].contains(wire.expects),
              request.interaction.tentativeMove != nil || ![.judgeMoveSafety, .chooseWhetherToPlay].contains(wire.expects)
        else { throw invalid }

        let hasDraft = request.interaction.tentativeMove != nil
        let pieces = hasDraft ? request.tentativePosition?.pieces ?? [] : request.pieces
        let relationships = hasDraft ? request.tentativePosition?.occupiedSquareRelationships ?? [] : request.occupiedSquareRelationships
        // Requests normally come from the native builder. Avoid traps on malformed imported fixtures.
        let bySquare = pieces.reduce(into: [String: ModelCoachingNeutralPiece]()) { $0[$1.square] = $1 }
        let byID = pieces.reduce(into: [String: ModelCoachingNeutralPiece]()) { $0[$1.id] = $1 }
        let references = content.runs.filter { $0.referencedSquare != nil }
        guard references.count <= 2 else { throw invalid }
        for run in content.runs {
            guard !run.text.isEmpty else { throw invalid }
            if let square = run.referencedSquare {
                guard isSquare(square), !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid }
                if case .piece = run, bySquare[square] == nil { throw invalid }
            }
        }

        let moves = Set(request.legalMoves.filter(\.isLegal).map { move in
            ModelCoachingChessNativeMoveFocus(from: String(move.canonicalMove.prefix(2)), to: String(move.canonicalMove.dropFirst(2).prefix(2)))
        })
        for cue in content.visuals {
            let ends = cue.endpoints
            guard isSquare(ends.from), isSquare(ends.to) else { throw invalid }
            switch cue {
            case .move: guard moves.contains(ends) else { throw invalid }
            case .attack:
                guard relationships.contains(where: {
                    $0.kind == .attacks && byID[$0.sourcePieceReference]?.square == ends.from
                        && byID[$0.targetPieceReference]?.square == ends.to
                }) else { throw invalid }
            }
        }

        if [.findEndangeredPiece, .findSafeCapture].contains(wire.expects) {
            let event = request.interaction.latestEvent
            let isHint = event.kind == .actionChosen && event.referencedIDs.contains("action:hint")
            guard content.visuals.isEmpty,
                  references.isEmpty || (isHint && references.count == 1) else { throw invalid }
            for run in references {
                guard case .piece(_, let square) = run, let piece = bySquare[square] else { throw invalid }
                let own = piece.color == request.position.sideToMove
                guard own == (wire.expects == .findSafeCapture) else { throw invalid }
            }
        }
        return turn
    }

    private static var invalid: ModelCoachingChessNativeTurnDecodingError { .validationFailed(["Invalid visual response."]) }

    private static func isSquare(_ value: String) -> Bool {
        value.range(of: #"^[a-h][1-8]$"#, options: .regularExpression) != nil
    }
}
