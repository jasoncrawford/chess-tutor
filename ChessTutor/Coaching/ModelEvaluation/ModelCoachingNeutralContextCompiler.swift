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
        var movesByID = Dictionary(uniqueKeysWithValues: request.legalMoves.map { ($0.id, $0) })
        if let tentativeMove = request.interaction.tentativeMove {
            movesByID[tentativeMove.id] = tentativeMove
        }
        request.tentativeReplies.forEach { movesByID[$0.id] = $0.move }
        let relationshipByID = Dictionary(
            uniqueKeysWithValues: request.occupiedSquareRelationships.map { ($0.id, $0) }
        )
        let replyRelationshipByID = Dictionary(
            uniqueKeysWithValues: request.tentativeReplies
                .flatMap(\.directRelationships)
                .map { ($0.id, $0) }
        )

        let inspectedReplies = inspectedReplies(in: request)

        let focusStableIDs = focusStableIDs(
            for: request,
            inspectedReplies: inspectedReplies
        )
        let actionStableIDs = actionStableIDs(for: request)
        let bindingTable = bindingTable(
            focusStableIDs: focusStableIDs,
            actionStableIDs: actionStableIDs,
            pieceByID: pieceByID,
            movesByID: movesByID,
            relationshipByID: relationshipByID,
            replyRelationshipByID: replyRelationshipByID
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
                    lines: episodeLines(
                        for: request,
                        bindings: bindingTable,
                        pieceByID: pieceByID,
                        movesByID: movesByID,
                        relationshipByID: relationshipByID,
                        replyRelationshipByID: replyRelationshipByID
                    )
                ),
                ModelCoachingMarkdownSection(
                    heading: "Rule facts",
                    lines: ruleFactLines(
                        for: request,
                        inspectedReplies: inspectedReplies,
                        bindings: bindingTable,
                        pieceByID: pieceByID,
                        relationshipByID: relationshipByID,
                        replyRelationshipByID: replyRelationshipByID
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
        bindings: BindingTable,
        pieceByID: [String: ModelCoachingNeutralPiece],
        movesByID: [String: ModelCoachingNeutralMove],
        relationshipByID: [String: ModelCoachingNeutralRelationship],
        replyRelationshipByID: [String: ModelCoachingNeutralReplyRelationship]
    ) -> [String] {
        request.interaction.episodeEvents.sorted { $0.sequence < $1.sequence }.map { event in
            let references = event.referencedIDs
                .sorted()
                .map {
                    referenceDescription(
                        for: $0,
                        bindings: bindings,
                        pieceByID: pieceByID,
                        movesByID: movesByID,
                        relationshipByID: relationshipByID,
                        replyRelationshipByID: replyRelationshipByID
                    )
                }
            let prefix = "\(event.sequence). \(eventLabel(event.kind))"
            if references.isEmpty {
                return prefix
            }
            return "\(prefix): \(references.joined(separator: ", "))"
        }
    }

    private static func ruleFactLines(
        for request: ModelCoachingNeutralRequest,
        inspectedReplies: [ModelCoachingNeutralReply],
        bindings: BindingTable,
        pieceByID: [String: ModelCoachingNeutralPiece],
        relationshipByID: [String: ModelCoachingNeutralRelationship],
        replyRelationshipByID: [String: ModelCoachingNeutralReplyRelationship]
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

        if !inspectedReplies.isEmpty,
           let inspectedPieceID = inspectedPieceID(in: request) {
            lines.append(
                inspectedPieceLine(
                    inspectedPieceID,
                    bindings: bindings,
                    pieceByID: pieceByID
                )
            )
            lines.append(inspectedRepliesLine(inspectedReplies, bindings: bindings))
            for reply in inspectedReplies {
                lines.append(
                    inspectedRelationshipLine(
                        reply: reply,
                        bindings: bindings,
                        replyRelationshipByID: replyRelationshipByID
                    )
                )
            }
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
            .map { "\($0.alias) (\($0.label))" }

        return [
            "Board gestures: \(gestures.joined(separator: ", "))",
            "Actions: \(actions.isEmpty ? "none" : actions.joined(separator: ", "))",
            "Focus: \(focus.isEmpty ? "none" : focus.joined(separator: ", "))",
        ]
    }

    private static func focusStableIDs(
        for request: ModelCoachingNeutralRequest,
        inspectedReplies: [ModelCoachingNeutralReply]
    ) -> [String] {
        var stableIDs = Set<String>()

        request.occupiedSquareRelationships
            .filter { $0.kind == .attacks }
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

        if let inspectedPieceID = inspectedPieceID(in: request), !inspectedReplies.isEmpty {
            stableIDs.insert(inspectedPieceID)
            for reply in inspectedReplies {
                stableIDs.insert(reply.id)
                reply.directRelationships.forEach { stableIDs.insert($0.id) }
            }
        }

        return stableIDs.sorted()
    }

    private static func actionStableIDs(for request: ModelCoachingNeutralRequest) -> [String] {
        var stableIDs = Set<String>()
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
        movesByID: [String: ModelCoachingNeutralMove],
        relationshipByID: [String: ModelCoachingNeutralRelationship],
        replyRelationshipByID: [String: ModelCoachingNeutralReplyRelationship]
    ) -> BindingTable {
        let focusDescriptors = focusStableIDs.compactMap { stableID -> BindingDescriptor? in
            if let piece = pieceByID[stableID] {
                return BindingDescriptor(
                    stableID: stableID,
                    category: .piece,
                    label: pieceLabel(piece)
                )
            }
            if let move = movesByID[stableID] {
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
            if let relationship = replyRelationshipByID[stableID] {
                return BindingDescriptor(
                    stableID: stableID,
                    category: .relationship,
                    label: replyRelationshipLabel(relationship)
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
        let relationships = request.occupiedSquareRelationships
            .filter { $0.kind == .attacks }
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
            return "\(alias) (\(moveLabel(reply.move)))"
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

    private static func inspectedPieceLine(
        _ pieceID: String,
        bindings: BindingTable,
        pieceByID: [String: ModelCoachingNeutralPiece]
    ) -> String {
        let alias = bindings.aliasByStableID[pieceID] ?? pieceID
        let label = pieceByID[pieceID].map(pieceLabel) ?? pieceID
        return "Inspected piece: \(alias) (\(label))"
    }

    private static func inspectedRepliesLine(
        _ replies: [ModelCoachingNeutralReply],
        bindings: BindingTable
    ) -> String {
        let entries = replies.sorted { $0.id < $1.id }.map { reply in
            let alias = bindings.aliasByStableID[reply.id] ?? reply.id
            return "\(alias) (\(moveLabel(reply.move)))"
        }
        return "Matching inspected replies: \(entries.joined(separator: ", "))"
    }

    private static func inspectedRelationshipLine(
        reply: ModelCoachingNeutralReply,
        bindings: BindingTable,
        replyRelationshipByID: [String: ModelCoachingNeutralReplyRelationship]
    ) -> String {
        let replyAlias = bindings.aliasByStableID[reply.id] ?? reply.id
        let entries: [String] = reply.directRelationships.sorted { $0.id < $1.id }.map { relationship in
            let canonical = replyRelationshipByID[relationship.id] ?? relationship
            let alias = bindings.aliasByStableID[canonical.id] ?? canonical.id
            return "\(alias) (\(replyRelationshipLabel(canonical)))"
        }
        return "Direct relationships for \(replyAlias): \(entries.isEmpty ? "none" : entries.joined(separator: ", "))"
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

    private static func eventLabel(_ kind: ModelCoachingLearnerEventKind) -> String {
        switch kind {
        case .helpOpened: return "Help opened"
        case .helpReopened: return "Help reopened"
        case .pieceSelected: return "Piece selected"
        case .squareInspected: return "Square inspected"
        case .moveStaged: return "Move staged"
        case .moveReplaced: return "Move replaced"
        case .moveRemoved: return "Move removed"
        case .actionChosen: return "Action chosen"
        case .helpClosed: return "Help closed"
        }
    }

    private static func referenceDescription(
        for stableID: String,
        bindings: BindingTable,
        pieceByID: [String: ModelCoachingNeutralPiece],
        movesByID: [String: ModelCoachingNeutralMove],
        relationshipByID: [String: ModelCoachingNeutralRelationship],
        replyRelationshipByID: [String: ModelCoachingNeutralReplyRelationship]
    ) -> String {
        if stableID.hasPrefix("action:") {
            return actionLabel(for: stableID)
        }
        if let binding = bindings.bindings.first(where: { $0.stableID == stableID }) {
            return "\(binding.alias) (\(binding.label))"
        }
        if let piece = pieceByID[stableID] {
            return pieceLabel(piece)
        }
        if let move = movesByID[stableID] {
            return moveLabel(move)
        }
        if let relationship = relationshipByID[stableID] {
            return relationshipLabel(relationship, pieceByID: pieceByID)
        }
        if let relationship = replyRelationshipByID[stableID] {
            return replyRelationshipLabel(relationship)
        }
        if stableID.hasPrefix("move:") {
            return String(stableID.dropFirst("move:".count))
        }
        let pieceComponents = stableID.split(separator: ":")
        if pieceComponents.count == 4, pieceComponents[0] == "piece" {
            return "\(displayColor(String(pieceComponents[1]))) \(pieceComponents[2]) on \(pieceComponents[3])"
        }
        return stableID
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

    private static func replyRelationshipLabel(
        _ relationship: ModelCoachingNeutralReplyRelationship
    ) -> String {
        let phase = relationship.phase == .afterTentative
            ? "After tentative move"
            : "After reply"
        let source = pieceLabel(relationship.sourcePiece)
        let target = pieceLabel(relationship.targetPiece)
        let verb: String
        switch relationship.kind {
        case .attacks: verb = "attacks"
        case .defends: verb = "defends"
        case .checks: verb = "checks"
        case .canCapture: verb = "can capture"
        case .canRecapture: verb = "can recapture"
        }
        return "\(phase), \(source) \(verb) \(target)"
    }

    private static func actionLabel(for stableID: String) -> String {
        let rawValue = stableID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? stableID
        switch rawValue {
        case "hint": return "Hint"
        case "noPieceNeedsHelp": return "No piece needs help"
        case "noSafeCapture": return "No safe capture"
        case "looksSafe": return "Looks safe"
        case "playMove": return "Play move"
        case "tryAnotherMove": return "Try another move"
        case "closeHelp": return "Close help"
        default: return rawValue
        }
    }

    private static func inspectedPieceID(in request: ModelCoachingNeutralRequest) -> String? {
        guard request.interaction.latestEvent.kind == .squareInspected,
              let inspectedPieceID = request.interaction.latestEvent.referencedIDs.first,
              request.interaction.tentativeMove != nil else {
            return nil
        }
        return inspectedPieceID
    }

    private static func inspectedReplies(
        in request: ModelCoachingNeutralRequest
    ) -> [ModelCoachingNeutralReply] {
        guard let inspectedPieceID = inspectedPieceID(in: request) else { return [] }
        return request.tentativeReplies
            .filter { $0.sourcePieceReference == inspectedPieceID }
            .sorted { $0.id < $1.id }
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
