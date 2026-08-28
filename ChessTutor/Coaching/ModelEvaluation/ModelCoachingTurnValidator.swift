enum ModelCoachingValidationIssue: Equatable, Sendable {
    case unsupportedTurnSchemaVersion
    case requestIDMismatch
    case unknownActionReference(String)
    case duplicateActionReference(String)
    case actionReferenceLimitExceeded
    case unknownBoardTaskReference(String)
    case unknownBoardFocusReference(String)
    case duplicateBoardFocusReference(String)
    case unknownRelationshipReference(String)
    case duplicateRelationshipReference(String)
    case unknownSupportingEvidenceReference(String)
    case duplicateSupportingEvidenceReference(String)
    case primaryMessageWordLimitExceeded
    case instructionWordLimitExceeded
    case responseWordLimitExceeded
    case actionTitleWordLimitExceeded(String)
    case missingSupportingEvidenceReference
}

enum ModelCoachingTurnValidator {
    static func validate(
        _ turn: ModelCoachingTurn,
        against request: ModelCoachingRequest,
        limits: ModelCoachingLimits = .default
    ) -> [ModelCoachingValidationIssue] {
        var issues: [ModelCoachingValidationIssue] = []

        if turn.schemaVersion != "model-coaching-turn.v1" {
            issues.append(.unsupportedTurnSchemaVersion)
        }

        if turn.requestID != request.requestID {
            issues.append(.requestIDMismatch)
        }

        let permittedActionIDs = Set(request.permittedReferences.actions.map(\.id))
        issues.append(contentsOf: unknownReferences(
            in: turn.actionReferences,
            permitted: permittedActionIDs,
            issue: ModelCoachingValidationIssue.unknownActionReference
        ))
        issues.append(contentsOf: duplicateReferences(
            in: turn.actionReferences,
            issue: ModelCoachingValidationIssue.duplicateActionReference
        ))
        if turn.actionReferences.count > limits.actionCount {
            issues.append(.actionReferenceLimitExceeded)
        }

        let permittedBoardTaskIDs = Set(request.permittedReferences.boardTasks.map(\.id))
        if let boardTaskReference = turn.boardTaskReference,
           !permittedBoardTaskIDs.contains(boardTaskReference) {
            issues.append(.unknownBoardTaskReference(boardTaskReference))
        }

        let permittedBoardFocusIDs = Set(request.permittedReferences.boardFocus)
        issues.append(contentsOf: unknownReferences(
            in: turn.boardFocusReferences,
            permitted: permittedBoardFocusIDs,
            issue: ModelCoachingValidationIssue.unknownBoardFocusReference
        ))
        issues.append(contentsOf: duplicateReferences(
            in: turn.boardFocusReferences,
            issue: ModelCoachingValidationIssue.duplicateBoardFocusReference
        ))

        let permittedRelationshipIDs = Set(request.permittedReferences.relationships)
        issues.append(contentsOf: unknownReferences(
            in: turn.relationshipReferences,
            permitted: permittedRelationshipIDs,
            issue: ModelCoachingValidationIssue.unknownRelationshipReference
        ))
        issues.append(contentsOf: duplicateReferences(
            in: turn.relationshipReferences,
            issue: ModelCoachingValidationIssue.duplicateRelationshipReference
        ))

        let permittedEvidenceIDs = Set(request.permittedReferences.evidence)
        issues.append(contentsOf: unknownReferences(
            in: turn.supportingEvidenceReferences,
            permitted: permittedEvidenceIDs,
            issue: ModelCoachingValidationIssue.unknownSupportingEvidenceReference
        ))
        issues.append(contentsOf: duplicateReferences(
            in: turn.supportingEvidenceReferences,
            issue: ModelCoachingValidationIssue.duplicateSupportingEvidenceReference
        ))

        if wordCount(in: turn.primaryMessage) > limits.primaryWords {
            issues.append(.primaryMessageWordLimitExceeded)
        }

        if let instruction = turn.instruction,
           wordCount(in: instruction) > limits.instructionWords {
            issues.append(.instructionWordLimitExceeded)
        }

        if let response = turn.responseToLatestAction,
           wordCount(in: response) > limits.responseWords {
            issues.append(.responseWordLimitExceeded)
        }

        for action in request.permittedReferences.actions where wordCount(in: action.title) > limits.actionTitleWords {
            issues.append(.actionTitleWordLimitExceeded(action.id))
        }

        if turn.supportingEvidenceReferences.isEmpty {
            issues.append(.missingSupportingEvidenceReference)
        }

        return issues
    }

    private static func unknownReferences(
        in references: [String],
        permitted: Set<String>,
        issue: (String) -> ModelCoachingValidationIssue
    ) -> [ModelCoachingValidationIssue] {
        var seen = Set<String>()

        return references.compactMap { reference in
            guard seen.insert(reference).inserted, !permitted.contains(reference) else {
                return nil
            }
            return issue(reference)
        }
    }

    private static func duplicateReferences(
        in references: [String],
        issue: (String) -> ModelCoachingValidationIssue
    ) -> [ModelCoachingValidationIssue] {
        var seen = Set<String>()
        var reportedDuplicates = Set<String>()

        return references.compactMap { reference in
            guard !seen.insert(reference).inserted, reportedDuplicates.insert(reference).inserted else {
                return nil
            }
            return issue(reference)
        }
    }

    private static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
