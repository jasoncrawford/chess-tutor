enum ModelCoachingChessNativeContextCompiler {
    static func compile(
        _ request: ModelCoachingNeutralRequest,
        promptVersion: String
    ) -> ModelCoachingChessNativeContextCompilation {
        let piecesByID = Dictionary(uniqueKeysWithValues: request.pieces.map { ($0.id, $0) })
        let scopedReplies = repliesForCurrentInteraction(in: request)
        let responseContract = responseContract(
            for: request,
            scopedReplies: scopedReplies
        )
        let document = ModelCoachingContextDocument(
            metadataLines: [],
            sections: [
                ModelCoachingMarkdownSection(
                    heading: "Position",
                    lines: positionLines(for: request)
                ),
                ModelCoachingMarkdownSection(
                    heading: "Latest interaction",
                    lines: latestInteractionLines(for: request, piecesByID: piecesByID)
                ),
                ModelCoachingMarkdownSection(
                    heading: "Relevant legal facts",
                    lines: relevantLegalFactLines(
                        for: request,
                        piecesByID: piecesByID,
                        scopedReplies: scopedReplies
                    )
                ),
                ModelCoachingMarkdownSection(
                    heading: "Available UI response",
                    lines: availableResponseLines(
                        actions: responseContract.availableActions,
                        moveFocus: responseContract.availableMoveFocus
                    )
                ),
            ]
        )

        return ModelCoachingChessNativeContextCompilation(
            schemaVersion: "model-coaching-chess-native-context.v1",
            promptVersion: promptVersion,
            requestID: request.requestID,
            positionRevision: request.positionRevision,
            markdown: ModelCoachingMarkdownRenderer.render(
                document,
                title: "# Chess coaching situation"
            ),
            availableActions: responseContract.availableActions,
            availableMoveFocus: responseContract.availableMoveFocus
        )
    }

    static func responseContract(
        for request: ModelCoachingNeutralRequest
    ) -> ModelCoachingChessNativeResponseContract {
        responseContract(
            for: request,
            scopedReplies: repliesForCurrentInteraction(in: request)
        )
    }

    private static func responseContract(
        for request: ModelCoachingNeutralRequest,
        scopedReplies: [ModelCoachingNeutralReply]
    ) -> ModelCoachingChessNativeResponseContract {
        ModelCoachingChessNativeResponseContract(
            availableActions: availableActions(in: request),
            availableMoveFocus: availableMoveFocus(
                in: request,
                scopedReplies: scopedReplies
            )
        )
    }

    private static func positionLines(for request: ModelCoachingNeutralRequest) -> [String] {
        [
            "Side to move: \(displayColor(request.position.sideToMove))",
            "Status: \(request.position.status)",
            "FEN: \(request.position.fen)",
            "Moves: \(historyLine(for: request.gameHistory))",
            "Tentative move: \(request.interaction.tentativeMove?.san ?? "none")",
        ]
    }

    private static func latestInteractionLines(
        for request: ModelCoachingNeutralRequest,
        piecesByID: [String: ModelCoachingNeutralPiece]
    ) -> [String] {
        let event = request.interaction.latestEvent
        let actor = displayColor(request.position.sideToMove)

        switch event.kind {
        case .helpOpened:
            return ["Help opened."]
        case .helpReopened:
            return ["Help reopened."]
        case .pieceSelected:
            let pieceID = request.interaction.selectedPieceReference ?? event.referencedIDs.first
            return ["\(actor) selected \(selectedPieceWithArticle(pieceID, piecesByID: piecesByID))."]
        case .squareInspected:
            return ["The child tapped \(pieceWithArticle(event.referencedIDs.first, piecesByID: piecesByID))."]
        case .moveStaged:
            return ["\(actor) tentatively played \(request.interaction.tentativeMove?.san ?? moveNotation(event.referencedIDs.first, in: request))."]
        case .moveReplaced:
            let oldMoveID = request.interaction.episodeEvents
                .filter { $0.sequence < event.sequence && ($0.kind == .moveStaged || $0.kind == .moveReplaced) }
                .max { $0.sequence < $1.sequence }?
                .referencedIDs.first
            let oldMove = moveNotation(oldMoveID, in: request)
            let currentMove = request.interaction.tentativeMove?.san
                ?? moveNotation(event.referencedIDs.first, in: request)
            return ["\(actor) replaced \(oldMove) with \(currentMove)."]
        case .moveRemoved:
            return ["\(actor) removed \(moveNotation(event.referencedIDs.first, in: request))."]
        case .actionChosen:
            let action = event.referencedIDs.first.map(actionName) ?? "an action"
            return ["The child chose \(action)."]
        case .helpClosed:
            return ["Help closed."]
        }
    }

    private static func relevantLegalFactLines(
        for request: ModelCoachingNeutralRequest,
        piecesByID: [String: ModelCoachingNeutralPiece],
        scopedReplies: [ModelCoachingNeutralReply]
    ) -> [String] {
        var lines = [checkStatusLine(for: request)]

        if let tentativeMove = request.interaction.tentativeMove {
            lines.append("Tentative move \(tentativeMove.san) is \(tentativeMove.isLegal ? "legal" : "not legal").")
            if let inspectedPieceID = inspectedPieceID(in: request) {
                lines.append("Inspected piece: \(pieceLabel(inspectedPieceID, piecesByID: piecesByID))")
                lines.append("Matching immediate replies: \(moveList(scopedReplies.map(\.move)))")
            } else {
                lines.append(
                    "Opponent immediate replies that capture, check, or mate: \(moveList(scopedReplies.map(\.move)))"
                )
            }
        } else if let selectedPieceID = request.interaction.selectedPieceReference {
            let selectedPiece = pieceLabel(selectedPieceID, piecesByID: piecesByID)
            let moves = request.legalMoves
                .filter { $0.sourcePieceReference == selectedPieceID }
                .sorted { $0.id < $1.id }
            lines.append("Selected piece: \(selectedPiece)")
            lines.append("Legal moves for \(selectedPiece): \(moveList(moves))")
        }

        return lines
    }

    private static func availableResponseLines(
        actions: [String],
        moveFocus: [ModelCoachingChessNativeMoveFocus]
    ) -> [String] {
        let moves = moveFocus.map { "\($0.from)-\($0.to)" }
        return [
            "Actions: \(actions.isEmpty ? "none" : actions.joined(separator: ", "))",
            "Square focus: any board square",
            "Allowable move focus: \(moves.isEmpty ? "none" : moves.joined(separator: ", "))",
        ]
    }

    private static func availableActions(in request: ModelCoachingNeutralRequest) -> [String] {
        var actions = ["hint"]
        if request.interaction.tentativeMove?.isLegal == true {
            actions.append("playMove")
        }
        if request.capabilities.canReplaceMove || request.capabilities.canRemoveMove {
            actions.append("tryAnotherMove")
        }
        return actions
    }

    private static func availableMoveFocus(
        in request: ModelCoachingNeutralRequest,
        scopedReplies: [ModelCoachingNeutralReply]
    ) -> [ModelCoachingChessNativeMoveFocus] {
        let moves: [ModelCoachingNeutralMove]
        if let tentativeMove = request.interaction.tentativeMove {
            moves = [tentativeMove] + scopedReplies.map(\.move)
        } else if let selectedPieceID = request.interaction.selectedPieceReference {
            moves = request.legalMoves
                .filter { $0.sourcePieceReference == selectedPieceID }
                .sorted { $0.id < $1.id }
        } else {
            moves = []
        }

        var seen = Set<ModelCoachingChessNativeMoveFocus>()
        return moves.compactMap { move in
            let focus = moveFocus(for: move)
            return seen.insert(focus).inserted ? focus : nil
        }
    }

    private static func repliesForCurrentInteraction(
        in request: ModelCoachingNeutralRequest
    ) -> [ModelCoachingNeutralReply] {
        let replies = request.tentativeReplies.sorted { $0.id < $1.id }
        guard let inspectedPieceID = inspectedPieceID(in: request) else {
            return replies
        }
        return replies.filter { $0.sourcePieceReference == inspectedPieceID }
    }

    private static func inspectedPieceID(in request: ModelCoachingNeutralRequest) -> String? {
        guard request.interaction.latestEvent.kind == .squareInspected,
              request.interaction.tentativeMove != nil,
              let inspectedPieceID = request.interaction.latestEvent.referencedIDs.first,
              let inspectedPiece = request.pieces.first(where: { $0.id == inspectedPieceID }),
              inspectedPiece.color != request.position.sideToMove else {
            return nil
        }
        return inspectedPieceID
    }

    private static func checkStatusLine(for request: ModelCoachingNeutralRequest) -> String {
        let side = displayColor(request.position.sideToMove)
        switch request.position.status {
        case "stalemate":
            return "\(side) is in stalemate."
        case let status where status.hasPrefix("checkmate:"):
            return "\(side) is in checkmate."
        default:
            let kingID = request.pieces.first {
                $0.color == request.position.sideToMove && $0.kind == "king"
            }?.id
            let inCheck = kingID.map { currentKingID in
                request.occupiedSquareRelationships.contains {
                    $0.kind == .checks && $0.targetPieceReference == currentKingID
                }
            } ?? false
            return "\(side) is \(inCheck ? "" : "not ")in check."
        }
    }

    private static func moveFocus(
        for move: ModelCoachingNeutralMove
    ) -> ModelCoachingChessNativeMoveFocus {
        ModelCoachingChessNativeMoveFocus(
            from: String(move.canonicalMove.prefix(2)),
            to: String(move.canonicalMove.dropFirst(2).prefix(2))
        )
    }

    private static func historyLine(for history: [ModelCoachingHistoryMove]) -> String {
        history.isEmpty ? "none" : history.map(\.displayNotation).joined(separator: " ")
    }

    private static func moveList(_ moves: [ModelCoachingNeutralMove]) -> String {
        moves.isEmpty ? "none" : moves.map(\.san).joined(separator: ", ")
    }

    private static func moveNotation(
        _ moveID: String?,
        in request: ModelCoachingNeutralRequest
    ) -> String {
        guard let moveID else { return "an unknown move" }
        let moves = request.legalMoves
            + request.tentativeReplies.map(\.move)
            + [request.interaction.tentativeMove].compactMap { $0 }
        if let move = moves.first(where: { $0.id == moveID }) {
            return move.san
        }
        guard moveID.hasPrefix("move:") else { return moveID }
        return String(moveID.dropFirst("move:".count))
    }

    private static func pieceWithArticle(
        _ pieceID: String?,
        piecesByID: [String: ModelCoachingNeutralPiece]
    ) -> String {
        guard let pieceID, let piece = piecesByID[pieceID] else {
            return "the piece"
        }
        return "the \(piece.color) \(piece.kind) on \(piece.square)"
    }

    private static func selectedPieceWithArticle(
        _ pieceID: String?,
        piecesByID: [String: ModelCoachingNeutralPiece]
    ) -> String {
        guard let pieceID, let piece = piecesByID[pieceID] else {
            return "the piece"
        }
        return "the \(piece.kind) on \(piece.square)"
    }

    private static func pieceLabel(
        _ pieceID: String,
        piecesByID: [String: ModelCoachingNeutralPiece]
    ) -> String {
        guard let piece = piecesByID[pieceID] else { return pieceID }
        return "\(displayColor(piece.color)) \(piece.kind) on \(piece.square)"
    }

    private static func actionName(_ actionID: String) -> String {
        actionID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? actionID
    }

    private static func displayColor(_ color: String) -> String {
        color.prefix(1).uppercased() + color.dropFirst()
    }
}
