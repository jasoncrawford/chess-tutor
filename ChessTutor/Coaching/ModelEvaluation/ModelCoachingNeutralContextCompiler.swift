import Foundation

struct ModelCoachingNeutralContextCompilation: Codable, Equatable, Sendable {
    let schemaVersion: String
    let promptVersion: String
    let requestID: String
    let positionRevision: Int
    let markdown: String
    let referenceBindings: [ModelCoachingReferenceBinding]
}

enum ModelCoachingNeutralContextCompiler {
    static func compile(
        _ request: ModelCoachingNeutralRequest,
        promptVersion: String
    ) -> ModelCoachingNeutralContextCompilation {
        let pieceByID = Dictionary(uniqueKeysWithValues: request.pieces.map { ($0.id, $0) })
        let legalMovesByID = Dictionary(uniqueKeysWithValues: request.legalMoves.map { ($0.id, $0) })
        let tentativeReplyByID = Dictionary(uniqueKeysWithValues: request.tentativeReplies.map { ($0.id, $0) })
        let relationshipByID = Dictionary(
            uniqueKeysWithValues: request.occupiedSquareRelationships.map { ($0.id, $0) }
        )

        let inspectedReplyID = inspectedReplyID(in: request)

        let focusStableIDs = focusStableIDs(
            for: request,
            inspectedReplyID: inspectedReplyID
        )
        let actionStableIDs = actionStableIDs(for: request)
        let bindingTable = bindingTable(
            focusStableIDs: focusStableIDs,
            actionStableIDs: actionStableIDs,
            pieceByID: pieceByID,
            legalMovesByID: legalMovesByID,
            tentativeReplyByID: tentativeReplyByID,
            relationshipByID: relationshipByID
        )

        let document = ModelCoachingContextDocument(
            metadataLines: [],
            sections: [
                ModelCoachingMarkdownSection(
                    heading: "Game",
                    lines: gameLines(for: request, bindings: bindingTable)
                ),
                ModelCoachingMarkdownSection(
                    heading: "Current help episode",
                    lines: episodeLines(for: request, bindings: bindingTable)
                ),
                ModelCoachingMarkdownSection(
                    heading: "Rule facts",
                    lines: ruleFactLines(
                        for: request,
                        inspectedReplyID: inspectedReplyID,
                        bindings: bindingTable,
                        pieceByID: pieceByID,
                        legalMovesByID: legalMovesByID,
                        tentativeReplyByID: tentativeReplyByID,
                        relationshipByID: relationshipByID
                    )
                ),
                ModelCoachingMarkdownSection(
                    heading: "Available interactions",
                    lines: availableInteractionLines(
                        for: request,
                        bindings: bindingTable
                    )
                ),
            ]
        )

        return ModelCoachingNeutralContextCompilation(
            schemaVersion: "model-coaching-neutral-context.v1",
            promptVersion: promptVersion,
            requestID: request.requestID,
            positionRevision: request.positionRevision,
            markdown: ModelCoachingMarkdownRenderer.render(
                document,
                title: "# Chess coaching situation"
            ),
            referenceBindings: bindingTable.bindings
        )
    }

    private static func gameLines(
        for request: ModelCoachingNeutralRequest,
        bindings: BindingTable
    ) -> [String] {
        [
            "Side to move: \(displayColor(request.position.sideToMove))",
            "Status: \(request.position.status)",
            "FEN: \(request.position.fen)",
            "Moves: \(historyLine(for: request.gameHistory))",
            "Tentative move: \(tentativeMoveLine(for: request.interaction.tentativeMove, bindings: bindings))",
        ]
    }

    private static func episodeLines(
        for request: ModelCoachingNeutralRequest,
        bindings: BindingTable
    ) -> [String] {
        request.interaction.episodeEvents.sorted { $0.sequence < $1.sequence }.map { event in
            let aliases = event.referencedIDs
                .sorted()
                .compactMap { bindings.aliasByStableID[$0] }
            if aliases.isEmpty {
                return "\(event.sequence). \(event.kind.rawValue)"
            }
            return "\(event.sequence). \(event.kind.rawValue) [\(aliases.joined(separator: ", "))]"
        }
    }

    private static func ruleFactLines(
        for request: ModelCoachingNeutralRequest,
        inspectedReplyID: String?,
        bindings: BindingTable,
        pieceByID: [String: ModelCoachingNeutralPiece],
        legalMovesByID: [String: ModelCoachingNeutralMove],
        tentativeReplyByID: [String: ModelCoachingNeutralReply],
        relationshipByID: [String: ModelCoachingNeutralRelationship]
    ) -> [String] {
        var lines = [
            checkLine(for: request, pieceByID: pieceByID, relationshipByID: relationshipByID),
            globalAttackLine(
                for: request,
                bindings: bindings,
                pieceByID: pieceByID,
                relationshipByID: relationshipByID
            ),
            legalMoveCategoryLine(
                title: "Legal captures",
                moves: request.legalMoves.filter { $0.capturePieceReference != nil },
                bindings: bindings
            ),
            legalMoveCategoryLine(
                title: "Checking moves",
                moves: request.legalMoves.filter { $0.givesCheck },
                bindings: bindings
            ),
            legalMoveCategoryLine(
                title: "Mating moves",
                moves: request.legalMoves.filter { $0.givesCheckmate },
                bindings: bindings
            ),
        ]

        if let tentativeMove = request.interaction.tentativeMove {
            lines.append(tentativeMoveFactLine(tentativeMove, bindings: bindings))
            lines.append(tentativeReplyLine(request.tentativeReplies, bindings: bindings))
        } else if let selectedPieceReference = request.interaction.selectedPieceReference {
            lines.append(selectedPieceLine(selectedPieceReference, bindings: bindings, pieceByID: pieceByID))
            lines.append(
                selectedMoveLine(
                    pieceID: selectedPieceReference,
                    request: request,
                    bindings: bindings
                )
            )
            lines.append(
                selectedRelationshipLine(
                    title: "Attackers on selected piece",
                    relationships: request.occupiedSquareRelationships.filter {
                        $0.kind == .attacks && $0.targetPieceReference == selectedPieceReference
                    },
                    bindings: bindings,
                    pieceByID: pieceByID
                )
            )
            lines.append(
                selectedRelationshipLine(
                    title: "Defenders of selected piece",
                    relationships: request.occupiedSquareRelationships.filter {
                        $0.kind == .defends
                            && $0.targetPieceReference == selectedPieceReference
                    },
                    bindings: bindings,
                    pieceByID: pieceByID
                )
            )
        }

        if let inspectedReplyID,
           let inspectedReply = tentativeReplyByID[inspectedReplyID] {
            lines.append(inspectedReplyLine(inspectedReply, bindings: bindings))
            lines.append(
                inspectedRelationshipLine(
                    reply: inspectedReply,
                    request: request,
                    bindings: bindings,
                    pieceByID: pieceByID
                )
            )
        }

        return lines
    }

    private static func availableInteractionLines(
        for request: ModelCoachingNeutralRequest,
        bindings: BindingTable
    ) -> [String] {
        let gestures = boardGestures(for: request.capabilities)
        let actions = bindings.bindings
            .filter { $0.category == .action }
            .sorted { $0.stableID < $1.stableID }
            .map { "\($0.alias) (\($0.label))" }
        let focus = bindings.bindings
            .filter { $0.category != .action }
            .sorted { $0.stableID < $1.stableID }
            .map(\.alias)

        return [
            "Board gestures: \(gestures.joined(separator: ", "))",
            "Actions: \(actions.isEmpty ? "none" : actions.joined(separator: ", "))",
            "Focus: \(focus.isEmpty ? "none" : focus.joined(separator: ", "))",
        ]
    }

    private static func focusStableIDs(
        for request: ModelCoachingNeutralRequest,
        inspectedReplyID: String?
    ) -> [String] {
        var stableIDs = Set(
            request.interaction.episodeEvents
                .flatMap(\.referencedIDs)
                .filter { !$0.hasPrefix("action:") }
        )

        let learnerColor = request.position.sideToMove
        let opposingColor = learnerColor == "white" ? "black" : "white"

        request.occupiedSquareRelationships
            .filter { relationship in
                relationship.kind == .attacks
                    && pieceColor(for: relationship.sourcePieceReference) == learnerColor
                    && pieceColor(for: relationship.targetPieceReference) == opposingColor
            }
            .forEach { stableIDs.insert($0.id) }

        request.legalMoves
            .filter { $0.capturePieceReference != nil || $0.givesCheck || $0.givesCheckmate }
            .forEach { stableIDs.insert($0.id) }

        if let tentativeMove = request.interaction.tentativeMove {
            stableIDs.insert(tentativeMove.id)
            request.tentativeReplies.forEach { stableIDs.insert($0.id) }
        } else if let selectedPieceReference = request.interaction.selectedPieceReference {
            stableIDs.insert(selectedPieceReference)
            request.legalMoves
                .filter { $0.sourcePieceReference == selectedPieceReference }
                .forEach { stableIDs.insert($0.id) }
            request.occupiedSquareRelationships
                .filter {
                    ($0.kind == .attacks || $0.kind == .defends || $0.kind == .checks)
                        && $0.targetPieceReference == selectedPieceReference
                }
                .forEach { stableIDs.insert($0.id) }
        }

        if let inspectedReplyID,
           let reply = request.tentativeReplies.first(where: { $0.id == inspectedReplyID }) {
            stableIDs.insert(inspectedReplyID)
            let relatedPieces = Set(
                [reply.sourcePieceReference, reply.capturePieceReference].compactMap { $0 }
            )
            request.occupiedSquareRelationships
                .filter {
                    ($0.kind == .attacks || $0.kind == .defends || $0.kind == .checks)
                        && (relatedPieces.contains($0.sourcePieceReference)
                            || relatedPieces.contains($0.targetPieceReference))
                }
                .forEach { stableIDs.insert($0.id) }
        }

        return stableIDs.sorted()
    }

    private static func actionStableIDs(for request: ModelCoachingNeutralRequest) -> [String] {
        var stableIDs = Set(
            request.interaction.episodeEvents
                .flatMap(\.referencedIDs)
                .filter { $0.hasPrefix("action:") }
        )

        stableIDs.insert(actionStableID(for: .hint))
        if request.capabilities.canReplaceMove || request.capabilities.canRemoveMove {
            stableIDs.insert(actionStableID(for: .tryAnotherMove))
        }
        if request.interaction.tentativeMove?.isLegal == true {
            stableIDs.insert(actionStableID(for: .playMove))
        }
        return stableIDs.sorted()
    }

    private static func bindingTable(
        focusStableIDs: [String],
        actionStableIDs: [String],
        pieceByID: [String: ModelCoachingNeutralPiece],
        legalMovesByID: [String: ModelCoachingNeutralMove],
        tentativeReplyByID: [String: ModelCoachingNeutralReply],
        relationshipByID: [String: ModelCoachingNeutralRelationship]
    ) -> BindingTable {
        let focusDescriptors = focusStableIDs.compactMap { stableID -> BindingDescriptor? in
            if let piece = pieceByID[stableID] {
                return BindingDescriptor(
                    stableID: stableID,
                    category: .piece,
                    label: pieceLabel(piece)
                )
            }
            if let move = legalMovesByID[stableID] ?? tentativeReplyByID[stableID] {
                return BindingDescriptor(
                    stableID: stableID,
                    category: .move,
                    label: moveLabel(move)
                )
            }
            if let relationship = relationshipByID[stableID] {
                return BindingDescriptor(
                    stableID: stableID,
                    category: .relationship,
                    label: relationshipLabel(
                        relationship,
                        pieceByID: pieceByID
                    )
                )
            }
            return nil
        }
        let actionDescriptors = actionStableIDs.map { stableID in
            BindingDescriptor(
                stableID: stableID,
                category: .action,
                label: actionLabel(for: stableID)
            )
        }

        let descriptors = (focusDescriptors + actionDescriptors).sorted { lhs, rhs in
            if lhs.category.rawValue != rhs.category.rawValue {
                return lhs.category.rawValue < rhs.category.rawValue
            }
            return lhs.stableID < rhs.stableID
        }

        let grouped = Dictionary(grouping: descriptors, by: \.category)
        var aliasByStableID: [String: String] = [:]
        var bindings: [ModelCoachingReferenceBinding] = []

        for category in ModelCoachingSourceReferenceCategory.allCasesForNeutralCompiler {
            let descriptorsForCategory = grouped[category, default: []].sorted { $0.stableID < $1.stableID }
            for (index, descriptor) in descriptorsForCategory.enumerated() {
                let alias = "\(category.aliasToken)-\(index + 1)"
                aliasByStableID[descriptor.stableID] = alias
                bindings.append(
                    ModelCoachingReferenceBinding(
                        alias: alias,
                        stableID: descriptor.stableID,
                        category: descriptor.category,
                        label: descriptor.label
                    )
                )
            }
        }

        bindings.sort { lhs, rhs in
            if lhs.category.rawValue != rhs.category.rawValue {
                return lhs.category.rawValue < rhs.category.rawValue
            }
            return lhs.stableID < rhs.stableID
        }

        return BindingTable(bindings: bindings, aliasByStableID: aliasByStableID)
    }

    private static func checkLine(
        for request: ModelCoachingNeutralRequest,
        pieceByID: [String: ModelCoachingNeutralPiece],
        relationshipByID: [String: ModelCoachingNeutralRelationship]
    ) -> String {
        let currentKingID = pieceByID.values.first {
            $0.kind == "king" && $0.color == request.position.sideToMove
        }?.id
        let isInCheck = currentKingID.map { kingID in
            relationshipByID.values.contains {
                $0.kind == .checks && $0.targetPieceReference == kingID
            }
        } ?? false

        return "\(displayColor(request.position.sideToMove)) is \(isInCheck ? "" : "not ")in check."
    }

    private static func globalAttackLine(
        for request: ModelCoachingNeutralRequest,
        bindings: BindingTable,
        pieceByID: [String: ModelCoachingNeutralPiece],
        relationshipByID: [String: ModelCoachingNeutralRelationship]
    ) -> String {
        let learnerColor = request.position.sideToMove
        let opposingColor = learnerColor == "white" ? "black" : "white"
        let relationships = request.occupiedSquareRelationships
            .filter { relationship in
                relationship.kind == .attacks
                    && pieceColor(for: relationship.sourcePieceReference) == learnerColor
                    && pieceColor(for: relationship.targetPieceReference) == opposingColor
            }
            .sorted { $0.id < $1.id }

        return relationshipCategoryLine(
            title: "Attacks on occupied opposing pieces",
            relationships: relationships,
            bindings: bindings,
            pieceByID: pieceByID
        )
    }

    private static func legalMoveCategoryLine(
        title: String,
        moves: [ModelCoachingNeutralMove],
        bindings: BindingTable
    ) -> String {
        let sortedMoves = moves.sorted { $0.id < $1.id }
        guard !sortedMoves.isEmpty else {
            return "\(title): none"
        }

        let entries = sortedMoves.map { move in
            let alias = bindings.aliasByStableID[move.id] ?? move.id
            return "\(alias) (\(moveLabel(move)))"
        }
        return "\(title): \(entries.joined(separator: ", "))"
    }

    private static func tentativeMoveFactLine(
        _ move: ModelCoachingNeutralMove,
        bindings: BindingTable
    ) -> String {
        let alias = bindings.aliasByStableID[move.id] ?? move.id
        return "Tentative move: \(alias) (\(moveLabel(move))) is \(move.isLegal ? "legal" : "not legal")."
    }

    private static func tentativeReplyLine(
        _ replies: [ModelCoachingNeutralReply],
        bindings: BindingTable
    ) -> String {
        let sortedReplies = replies.sorted { $0.id < $1.id }
        guard !sortedReplies.isEmpty else {
            return "Opponent replies that capture, check, or mate: none"
        }
        let entries = sortedReplies.map { reply in
            let alias = bindings.aliasByStableID[reply.id] ?? reply.id
            return "\(alias) (\(moveLabel(reply)))"
        }
        return "Opponent replies that capture, check, or mate: \(entries.joined(separator: ", "))"
    }

    private static func selectedPieceLine(
        _ pieceID: String,
        bindings: BindingTable,
        pieceByID: [String: ModelCoachingNeutralPiece]
    ) -> String {
        let alias = bindings.aliasByStableID[pieceID] ?? pieceID
        let label = pieceByID[pieceID].map(pieceLabel) ?? pieceID
        return "Selected piece: \(alias) (\(label))"
    }

    private static func selectedMoveLine(
        pieceID: String,
        request: ModelCoachingNeutralRequest,
        bindings: BindingTable
    ) -> String {
        let moves = request.legalMoves
            .filter { $0.sourcePieceReference == pieceID }
            .sorted { $0.id < $1.id }
        guard !moves.isEmpty else {
            return "Legal moves for selected piece: none"
        }
        let entries = moves.map { move in
            let alias = bindings.aliasByStableID[move.id] ?? move.id
            return "\(alias) (\(moveLabel(move)))"
        }
        return "Legal moves for selected piece: \(entries.joined(separator: ", "))"
    }

    private static func selectedRelationshipLine(
        title: String,
        relationships: [ModelCoachingNeutralRelationship],
        bindings: BindingTable,
        pieceByID: [String: ModelCoachingNeutralPiece]
    ) -> String {
        relationshipCategoryLine(
            title: title,
            relationships: relationships,
            bindings: bindings,
            pieceByID: pieceByID
        )
    }

    private static func inspectedReplyLine(
        _ reply: ModelCoachingNeutralReply,
        bindings: BindingTable
    ) -> String {
        let alias = bindings.aliasByStableID[reply.id] ?? reply.id
        return "Inspected reply: \(alias) (\(moveLabel(reply)))"
    }

    private static func inspectedRelationshipLine(
        reply: ModelCoachingNeutralReply,
        request: ModelCoachingNeutralRequest,
        bindings: BindingTable,
        pieceByID: [String: ModelCoachingNeutralPiece]
    ) -> String {
        let relatedPieces = Set([reply.sourcePieceReference, reply.capturePieceReference].compactMap { $0 })
        let relationships = request.occupiedSquareRelationships.filter {
            relatedPieces.contains($0.sourcePieceReference)
                || relatedPieces.contains($0.targetPieceReference)
        }
        return relationshipCategoryLine(
            title: "Direct relationships for inspected reply",
            relationships: relationships,
            bindings: bindings,
            pieceByID: pieceByID
        )
    }

    private static func relationshipCategoryLine(
        title: String,
        relationships: [ModelCoachingNeutralRelationship],
        bindings: BindingTable,
        pieceByID: [String: ModelCoachingNeutralPiece]
    ) -> String {
        let sortedRelationships = relationships.sorted { $0.id < $1.id }
        guard !sortedRelationships.isEmpty else {
            return "\(title): none"
        }
        let entries = sortedRelationships.map { relationship in
            let alias = bindings.aliasByStableID[relationship.id] ?? relationship.id
            return "\(alias) (\(relationshipLabel(relationship, pieceByID: pieceByID)))"
        }
        return "\(title): \(entries.joined(separator: ", "))"
    }

    private static func boardGestures(for capabilities: ModelCoachingNeutralCapabilities) -> [String] {
        var gestures: [String] = []
        if capabilities.canSelectBoardPiece {
            gestures.append("selectBoardPiece")
        }
        if capabilities.canInspectSquare {
            gestures.append("inspectSquare")
        }
        if capabilities.canStageMove {
            gestures.append("stageMove")
        }
        if capabilities.canReplaceMove {
            gestures.append("replaceMove")
        }
        if capabilities.canRemoveMove {
            gestures.append("removeMove")
        }
        return gestures
    }

    private static func historyLine(for history: [ModelCoachingHistoryMove]) -> String {
        guard !history.isEmpty else { return "none" }
        return history.map(\.displayNotation).joined(separator: " ")
    }

    private static func tentativeMoveLine(
        for move: ModelCoachingNeutralMove?,
        bindings: BindingTable
    ) -> String {
        guard let move else { return "none" }
        let alias = bindings.aliasByStableID[move.id] ?? move.id
        return "\(alias) (\(moveLabel(move)))"
    }

    private static func displayColor(_ color: String) -> String {
        color.prefix(1).uppercased() + color.dropFirst()
    }

    private static func pieceLabel(_ piece: ModelCoachingNeutralPiece) -> String {
        "\(displayColor(piece.color)) \(piece.kind) on \(piece.square)"
    }

    private static func moveLabel(_ move: ModelCoachingNeutralMove) -> String {
        move.san
    }

    private static func relationshipLabel(
        _ relationship: ModelCoachingNeutralRelationship,
        pieceByID: [String: ModelCoachingNeutralPiece]
    ) -> String {
        let source = pieceByID[relationship.sourcePieceReference].map(pieceLabel) ?? relationship.sourcePieceReference
        let target = pieceByID[relationship.targetPieceReference].map(pieceLabel) ?? relationship.targetPieceReference
        switch relationship.kind {
        case .attacks:
            return "\(source) attacks \(target)"
        case .defends:
            return "\(source) defends \(target)"
        case .checks:
            return "\(source) checks \(target)"
        case .canCapture:
            return "\(source) can capture \(target)"
        case .canRecapture:
            return "\(source) can recapture \(target)"
        }
    }

    private static func actionLabel(for stableID: String) -> String {
        stableID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? stableID
    }

    private static func pieceColor(for pieceID: String) -> String? {
        let parts = pieceID.split(separator: ":")
        guard parts.count >= 4, parts[0] == "piece" else { return nil }
        return String(parts[1])
    }

    private static func inspectedReplyID(in request: ModelCoachingNeutralRequest) -> String? {
        guard request.interaction.latestEvent.kind == .squareInspected,
              let inspectedPieceID = request.interaction.latestEvent.referencedIDs.first,
              request.interaction.tentativeMove != nil else {
            return nil
        }

        return request.tentativeReplies
            .filter { $0.sourcePieceReference == inspectedPieceID }
            .sorted { $0.id < $1.id }
            .first?
            .id
    }

    private static func actionStableID(for operation: ModelCoachingOperation) -> String {
        "action:\(operation.rawValue)"
    }
}

private struct BindingDescriptor {
    let stableID: String
    let category: ModelCoachingSourceReferenceCategory
    let label: String
}

private struct BindingTable {
    let bindings: [ModelCoachingReferenceBinding]
    let aliasByStableID: [String: String]
}

private extension ModelCoachingSourceReferenceCategory {
    static let allCasesForNeutralCompiler: [Self] = [
        .action,
        .piece,
        .move,
        .relationship,
    ]

    var aliasToken: String {
        switch self {
        case .action:
            return "action"
        case .boardTask:
            return "task"
        case .piece:
            return "piece"
        case .move:
            return "move"
        case .relationship:
            return "relationship"
        case .reply:
            return "reply"
        case .tacticalFact:
            return "fact"
        }
    }
}
