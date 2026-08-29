import Foundation

enum ModelCoachingContextCompiler {
    static func compile(
        _ request: ModelCoachingRequest,
        promptVersion: String
    ) throws -> ModelCoachingContextCompilation {
        let sources = sourceReferences(in: request)
        var selectedIDs = Set<String>()

        func include(_ stableID: String) {
            guard sources[stableID] != nil, selectedIDs.insert(stableID).inserted else {
                return
            }

            if let move = request.chessEvidence.legalMoves.first(where: { $0.id == stableID }) {
                include(move.sourcePieceReference)
                if let capture = move.capturePieceReference {
                    include(capture)
                }
            } else if let relationship = request.chessEvidence.relationships.first(where: { $0.id == stableID }) {
                include(relationship.sourceReference)
                include(relationship.targetReference)
            } else if let reply = request.chessEvidence.immediateReplies.first(where: { $0.id == stableID }) {
                include(reply.afterMoveReference)
                if let capture = reply.capturedPieceReference {
                    include(capture)
                }
                reply.checkingPieceReferences.forEach(include)
            } else if let fact = request.chessEvidence.tacticalFacts.first(where: { $0.id == stableID }) {
                fact.subjectReferences.forEach(include)
            }
        }

        request.permittedReferences.actions.map(\.id).forEach(include)
        request.permittedReferences.boardTasks.map(\.id).forEach(include)

        let priorityFactKinds: Set<ModelCoachingTacticalFactKind> = [
            .inCheck,
            .checkmate,
            .stalemate,
            .dangerLoss,
            .mateInOne,
            .noImmediateDanger,
            .noUsefulSafeCapture,
        ]
        for fact in request.chessEvidence.tacticalFacts where
            priorityFactKinds.contains(fact.kind)
                || (fact.kind == .exchangeGain && (fact.integerValue ?? 0) >= 1) {
            include(fact.id)
        }

        if let selectedPiece = request.currentInteraction.selectedPieceReference {
            include(selectedPiece)
        }
        request.currentInteraction.latestEvent.referencedIDs.forEach(include)

        let currentMoveID = authoritativeMoveReference(in: request)
        if let currentMoveID {
            include(currentMoveID)
            if let consequence = request.chessEvidence.moveConsequences.first(where: {
                $0.moveReference == currentMoveID
            }) {
                consequence.criticalReplyReferences.forEach(include)
            }
        }

        let dangerTargetIDs = Set(
            request.chessEvidence.tacticalFacts
                .filter { $0.kind == .dangerLoss }
                .flatMap(\.subjectReferences)
        )
        for relationship in request.chessEvidence.relationships where
            relationship.kind == .attacks && dangerTargetIDs.contains(relationship.targetReference) {
            include(relationship.id)
        }

        var selectedMoveIdeas: [ModelCoachingMoveReference] = []
        var eligibleMoveIdeaCount = 0
        if currentMoveID == nil {
            let moveIdeas = wakeMoveIdeas(in: request)
            selectedMoveIdeas = moveIdeas.selected
            eligibleMoveIdeaCount = moveIdeas.eligible.count
            selectedMoveIdeas.map(\.id).forEach(include)
        }

        for relationship in request.chessEvidence.relationships where
            selectedIDs.contains(relationship.sourceReference)
                && selectedIDs.contains(relationship.targetReference) {
            include(relationship.id)
        }

        let bindings = referenceBindings(
            for: sources.values.filter { selectedIDs.contains($0.stableID) }
        )
        let aliasesByStableID = Dictionary(
            uniqueKeysWithValues: bindings.map { ($0.stableID, $0.alias) }
        )
        let omissions = sources.values
            .filter { !selectedIDs.contains($0.stableID) }
            .map { source in
                ModelCoachingReferenceOmission(
                    stableID: source.stableID,
                    category: source.category,
                    reason: omissionReason(for: source)
                )
            }
            .sorted { $0.stableID < $1.stableID }
        let document = document(
            for: request,
            promptVersion: promptVersion,
            bindings: bindings,
            aliasesByStableID: aliasesByStableID,
            currentMoveID: currentMoveID,
            selectedMoveIdeas: selectedMoveIdeas,
            eligibleMoveIdeaCount: eligibleMoveIdeaCount
        )

        return ModelCoachingContextCompilation(
            schemaVersion: "model-coaching-context.v1",
            promptVersion: promptVersion,
            requestID: request.requestID,
            positionRevision: request.positionRevision,
            markdown: ModelCoachingMarkdownRenderer.render(document),
            referenceBindings: bindings,
            omissions: omissions
        )
    }

    private struct SourceReference {
        let stableID: String
        let category: ModelCoachingSourceReferenceCategory
        let label: String
        let aliasBase: String
    }

    private struct MoveIdeaSelection {
        let selected: [ModelCoachingMoveReference]
        let eligible: [ModelCoachingMoveReference]
    }

    private static func sourceReferences(
        in request: ModelCoachingRequest
    ) -> [String: SourceReference] {
        let piecesByID = Dictionary(
            uniqueKeysWithValues: request.chessEvidence.pieces.map { ($0.id, $0) }
        )
        var sources: [String: SourceReference] = [:]

        func add(
            _ stableID: String,
            category: ModelCoachingSourceReferenceCategory,
            label: String,
            aliasBase: String
        ) {
            precondition(sources[stableID] == nil, "Duplicate model coaching source reference: \(stableID)")
            sources[stableID] = SourceReference(
                stableID: stableID,
                category: category,
                label: label,
                aliasBase: aliasBase
            )
        }

        for action in request.permittedReferences.actions {
            add(
                action.id,
                category: .action,
                label: humanized(action.kind.rawValue),
                aliasBase: "action-\(kebab(action.kind.rawValue))"
            )
        }
        for task in request.permittedReferences.boardTasks {
            add(
                task.id,
                category: .boardTask,
                label: task.kind.rawValue,
                aliasBase: "task-\(kebab(task.kind.rawValue))"
            )
        }
        for piece in request.chessEvidence.pieces {
            add(
                piece.id,
                category: .piece,
                label: "\(piece.color.capitalized) \(piece.kind) on \(piece.square)",
                aliasBase: kebab(piece.id)
            )
        }
        for move in request.chessEvidence.legalMoves {
            let pieceKind = piecesByID[move.sourcePieceReference]?.kind.capitalized ?? "Piece"
            add(
                move.id,
                category: .move,
                label: "\(pieceKind) \(canonicalDescription(for: move))",
                aliasBase: kebab(move.id)
            )
        }
        for relationship in request.chessEvidence.relationships {
            let source = piecesByID[relationship.sourceReference]
                .map { "\($0.color) \($0.kind) \($0.square)" } ?? relationship.sourceReference
            let target = piecesByID[relationship.targetReference]
                .map { "\($0.color) \($0.kind) \($0.square)" } ?? relationship.targetReference
            add(
                relationship.id,
                category: .relationship,
                label: "\(source) \(relationship.kind.rawValue) \(target)",
                aliasBase: "relationship-\(kebab(relationship.kind.rawValue))"
            )
        }
        for reply in request.chessEvidence.immediateReplies {
            add(
                reply.id,
                category: .reply,
                label: "Reply \(shortMove(reply.replyMoveReference)) after \(shortMove(reply.afterMoveReference))",
                aliasBase: "reply-\(kebab(shortMove(reply.replyMoveReference)))"
            )
        }
        for fact in request.chessEvidence.tacticalFacts {
            add(
                fact.id,
                category: .tacticalFact,
                label: tacticalFactLabel(fact, piecesByID: piecesByID),
                aliasBase: "fact-\(kebab(fact.kind.rawValue))"
            )
        }
        return sources
    }

    private static func referenceBindings(
        for sources: [SourceReference]
    ) -> [ModelCoachingReferenceBinding] {
        var aliasesInUse: [String: Int] = [:]
        return sources.sorted { $0.stableID < $1.stableID }.map { source in
            let occurrence = (aliasesInUse[source.aliasBase] ?? 0) + 1
            aliasesInUse[source.aliasBase] = occurrence
            let alias = occurrence == 1
                ? source.aliasBase
                : "\(source.aliasBase)-\(occurrence)"
            return ModelCoachingReferenceBinding(
                alias: alias,
                stableID: source.stableID,
                category: source.category,
                label: source.label
            )
        }
    }

    private static func omissionReason(for source: SourceReference) -> ModelCoachingOmissionReason {
        switch source.category {
        case .reply:
            return .redundantReply
        case .move:
            return .lowerPriorityCandidate
        case .piece:
            return .unrelatedPiece
        case .relationship:
            return .unrelatedRelationship
        case .tacticalFact:
            return .representedByCompleteSummary
        case .action, .boardTask:
            preconditionFailure("Actions and board tasks must always be bound")
        }
    }

    private static func authoritativeMoveReference(
        in request: ModelCoachingRequest
    ) -> String? {
        if let tentative = request.currentInteraction.tentativeMoveReference {
            return tentative
        }
        switch request.currentInteraction.latestEvent.kind {
        case .moveStaged, .moveReplaced, .moveRemoved:
            let legalMoveIDs = Set(request.chessEvidence.legalMoves.map(\.id))
            return request.currentInteraction.latestEvent.referencedIDs.first {
                legalMoveIDs.contains($0)
            }
        case .helpOpened, .helpReopened, .pieceSelected, .squareInspected, .actionChosen, .helpClosed:
            return nil
        }
    }

    private static func wakeMoveIdeas(in request: ModelCoachingRequest) -> MoveIdeaSelection {
        let piecesByID = Dictionary(
            uniqueKeysWithValues: request.chessEvidence.pieces.map { ($0.id, $0) }
        )
        let legalMoves = request.chessEvidence.legalMoves.sorted { $0.id < $1.id }
        let castling = legalMoves.filter { $0.special.lowercased().contains("castle") }
        let development = legalMoves.filter { move in
            guard let piece = piecesByID[move.sourcePieceReference],
                  ["knight", "bishop"].contains(piece.kind) else {
                return false
            }
            let originalSquares: Set<String> = piece.color == "white"
                ? ["b1", "c1", "f1", "g1"]
                : ["b8", "c8", "f8", "g8"]
            return originalSquares.contains(piece.square)
        }
        let centerPawns = legalMoves.filter { move in
            guard let piece = piecesByID[move.sourcePieceReference], piece.kind == "pawn" else {
                return false
            }
            return ["d", "e"].contains(String(piece.square.prefix(1)))
                && ["4", "5"].contains(String(move.destinationSquare.suffix(1)))
        }
        let selectedPieceMoves = legalMoves.filter {
            $0.sourcePieceReference == request.currentInteraction.selectedPieceReference
        }
        let groups = [castling, development, centerPawns, selectedPieceMoves]
        let eligible = uniqueMoves(groups.flatMap { $0 })
        var selected: [ModelCoachingMoveReference] = []
        for group in groups where selected.count < 3 {
            if let candidate = group.first(where: { move in
                !selected.contains(where: { $0.id == move.id })
            }) {
                selected.append(candidate)
            }
        }
        return MoveIdeaSelection(selected: selected, eligible: eligible)
    }

    private static func uniqueMoves(
        _ moves: [ModelCoachingMoveReference]
    ) -> [ModelCoachingMoveReference] {
        var seen: Set<String> = []
        return moves.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
    }

    private static func document(
        for request: ModelCoachingRequest,
        promptVersion: String,
        bindings: [ModelCoachingReferenceBinding],
        aliasesByStableID: [String: String],
        currentMoveID: String?,
        selectedMoveIdeas: [ModelCoachingMoveReference],
        eligibleMoveIdeaCount: Int
    ) -> ModelCoachingContextDocument {
        var sections = [
            currentSituationSection(request, aliasesByStableID: aliasesByStableID),
            latestActionSection(request, aliasesByStableID: aliasesByStableID),
            historySection(request),
            tacticalSummarySection(request, aliasesByStableID: aliasesByStableID),
        ]
        if let currentMoveID,
           let move = request.chessEvidence.legalMoves.first(where: { $0.id == currentMoveID }) {
            sections.append(stagedMoveSection(
                request,
                move: move,
                aliasesByStableID: aliasesByStableID
            ))
        } else if !selectedMoveIdeas.isEmpty {
            sections.append(moveIdeasSection(
                selectedMoveIdeas,
                eligibleCount: eligibleMoveIdeaCount,
                aliasesByStableID: aliasesByStableID
            ))
        }
        sections.append(responseReferencesSection(bindings))

        return ModelCoachingContextDocument(
            metadataLines: [
                "- Schema: `model-coaching-context.v1`",
                "- Prompt: `\(promptVersion)`",
                "- Request: `\(request.requestID)`",
                "- Position revision: \(request.positionRevision)",
            ],
            sections: sections
        )
    }

    private static func currentSituationSection(
        _ request: ModelCoachingRequest,
        aliasesByStableID: [String: String]
    ) -> ModelCoachingMarkdownSection {
        var lines = [
            "FEN:",
            "```text",
            request.currentPosition.fen,
            "```",
            "- Side to move: \(request.currentPosition.sideToMove)",
            "- Status: \(request.currentPosition.status)",
        ]
        if let selected = request.currentInteraction.selectedPieceReference {
            lines.append("- Selected piece: \(aliasesByStableID[selected] ?? selected)")
        }
        if let tentative = request.currentInteraction.tentativeMoveReference {
            lines.append("- Tentative move: \(aliasesByStableID[tentative] ?? tentative)")
        }
        return ModelCoachingMarkdownSection(heading: "# Current situation", lines: lines)
    }

    private static func latestActionSection(
        _ request: ModelCoachingRequest,
        aliasesByStableID: [String: String]
    ) -> ModelCoachingMarkdownSection {
        var lines = ["- Latest event: \(request.currentInteraction.latestEvent.kind.rawValue)"]
        let references = request.currentInteraction.latestEvent.referencedIDs.compactMap {
            aliasesByStableID[$0]
        }
        if !references.isEmpty {
            lines.append("- Event references: \(references.joined(separator: ", "))")
        }
        return ModelCoachingMarkdownSection(heading: "Latest action", lines: lines)
    }

    private static func historySection(
        _ request: ModelCoachingRequest
    ) -> ModelCoachingMarkdownSection {
        var lines: [String]
        if request.fullGameHistory.isEmpty {
            lines = ["- Game history: no committed moves."]
        } else {
            lines = [
                "- Game history: \(request.fullGameHistory.map(\.displayNotation).joined(separator: " "))"
            ]
        }
        if request.currentTurnCoachingHistory.isEmpty {
            lines.append("- Current-turn history: none.")
        } else {
            lines.append("- Current-turn history:")
            lines += request.currentTurnCoachingHistory.map {
                "  \($0.sequence). [\($0.kind.rawValue)] \($0.summary)"
            }
        }
        return ModelCoachingMarkdownSection(heading: "History", lines: lines)
    }

    private static func tacticalSummarySection(
        _ request: ModelCoachingRequest,
        aliasesByStableID: [String: String]
    ) -> ModelCoachingMarkdownSection {
        let facts = request.chessEvidence.tacticalFacts
        var lines = ["- Position status — complete: \(request.currentPosition.status)."]
        let dangerFacts = facts.filter { $0.kind == .dangerLoss }
        if facts.contains(where: { $0.kind == .noImmediateDanger }) {
            lines.append("- Danger scan — complete: no learner piece is in immediate danger.")
        } else if !dangerFacts.isEmpty {
            lines.append("- Danger scan — complete:")
            lines += dangerFacts.map { fact in
                "  - \(aliasesByStableID[fact.id] ?? fact.id): immediate estimated loss \(abs(fact.integerValue ?? 0))."
            }
        }

        let captureFacts = facts.filter {
            $0.kind == .exchangeGain && ($0.integerValue ?? 0) >= 1
        }
        if facts.contains(where: { $0.kind == .noUsefulSafeCapture }) {
            lines.append("- Safe captures — complete: no useful safe capture exists.")
        } else if !captureFacts.isEmpty {
            lines.append("- Safe captures — complete:")
            lines += captureFacts.map { fact in
                "  - \(aliasesByStableID[fact.id] ?? fact.id): estimated gain \(fact.integerValue ?? 0)."
            }
        }

        let mateFacts = facts.filter { $0.kind == .mateInOne }
        if !mateFacts.isEmpty {
            lines.append("- Mate in one — complete:")
            lines += mateFacts.map { fact in
                "  - \(aliasesByStableID[fact.id] ?? fact.id)"
            }
        }
        return ModelCoachingMarkdownSection(
            heading: "Complete tactical summary",
            lines: lines
        )
    }

    private static func stagedMoveSection(
        _ request: ModelCoachingRequest,
        move: ModelCoachingMoveReference,
        aliasesByStableID: [String: String]
    ) -> ModelCoachingMarkdownSection {
        let consequence = request.chessEvidence.moveConsequences.first {
            $0.moveReference == move.id
        }
        let status: String
        if request.currentInteraction.latestEvent.kind == .moveRemoved {
            status = "removed"
        } else if request.currentInteraction.latestEvent.kind == .moveReplaced {
            status = "replacement staged"
        } else {
            status = "staged"
        }
        var lines = [
            "- Move: \(aliasesByStableID[move.id] ?? move.id) — \(canonicalDescription(for: move))",
            "- Current status: \(status)",
            "- Legal: \(consequence?.isLegal == true ? "yes" : "no")",
        ]
        if let consequence, consequence.issueKinds.isEmpty {
            lines.append("- No immediate tactical refutation was found.")
        } else if let consequence {
            lines.append("- Unsafe issues: \(consequence.issueKinds.map(\.rawValue).joined(separator: ", "))")
            if consequence.worstEstimatedLoss > 0 {
                lines.append("- Worst estimated loss: \(consequence.worstEstimatedLoss)")
            }
            for reply in consequence.criticalReplyReferences {
                lines.append("- Critical reply: \(aliasesByStableID[reply] ?? reply)")
            }
        }
        return ModelCoachingMarkdownSection(heading: "Staged move", lines: lines)
    }

    private static func moveIdeasSection(
        _ moves: [ModelCoachingMoveReference],
        eligibleCount: Int,
        aliasesByStableID: [String: String]
    ) -> ModelCoachingMarkdownSection {
        var lines = ["- Development candidates — selected \(moves.count) of \(eligibleCount):"]
        lines += moves.map { move in
            "  - \(aliasesByStableID[move.id] ?? move.id): \(canonicalDescription(for: move))"
        }
        return ModelCoachingMarkdownSection(heading: "Selected move ideas", lines: lines)
    }

    private static func responseReferencesSection(
        _ bindings: [ModelCoachingReferenceBinding]
    ) -> ModelCoachingMarkdownSection {
        var lines: [String] = []
        for category in [
            ModelCoachingSourceReferenceCategory.action,
            .boardTask,
            .piece,
            .move,
            .relationship,
            .reply,
            .tacticalFact,
        ] {
            let categoryBindings = bindings.filter { $0.category == category }
            guard !categoryBindings.isEmpty else { continue }
            lines.append("- \(humanized(category.rawValue)):")
            lines += categoryBindings.map { "  - \($0.alias) — \($0.label)" }
        }
        return ModelCoachingMarkdownSection(
            heading: "Available response references",
            lines: lines
        )
    }

    private static func tacticalFactLabel(
        _ fact: ModelCoachingTacticalFact,
        piecesByID: [String: ModelCoachingPieceReference]
    ) -> String {
        let subjects = fact.subjectReferences.map { reference in
            if let piece = piecesByID[reference] {
                return "\(piece.color) \(piece.kind) \(piece.square)"
            }
            return shortMove(reference)
        }
        return ([humanized(fact.kind.rawValue)] + subjects).joined(separator: ": ")
    }

    private static func canonicalDescription(for move: ModelCoachingMoveReference) -> String {
        shortMove(move.id)
    }

    private static func shortMove(_ reference: String) -> String {
        reference.replacingOccurrences(of: "move:", with: "")
    }

    private static func humanized(_ value: String) -> String {
        kebab(value)
            .split(separator: "-")
            .joined(separator: " ")
            .capitalized
    }

    private static func kebab(_ value: String) -> String {
        var characters: [Character] = []
        for character in value {
            if character.isASCII && (character.isLetter || character.isNumber) {
                if character.isUppercase, let last = characters.last, last != "-" {
                    characters.append("-")
                }
                characters.append(Character(character.lowercased()))
            } else if characters.last != "-" {
                characters.append("-")
            }
        }
        return String(characters).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
