struct ModelCoachingContextCompilation: Codable, Equatable, Sendable {
    let schemaVersion: String
    let promptVersion: String
    let requestID: String
    let positionRevision: Int
    let markdown: String
    let referenceBindings: [ModelCoachingReferenceBinding]
    let omissions: [ModelCoachingReferenceOmission]
}

struct ModelCoachingContextDocument: Equatable, Sendable {
    let metadataLines: [String]
    let sections: [ModelCoachingMarkdownSection]
}

struct ModelCoachingMarkdownSection: Equatable, Sendable {
    let heading: String
    let lines: [String]
}

struct ModelCoachingReferenceBinding: Codable, Equatable, Sendable {
    let alias: String
    let stableID: String
    let category: ModelCoachingSourceReferenceCategory
    let label: String
}

struct ModelCoachingReferenceOmission: Codable, Equatable, Sendable {
    let stableID: String
    let category: ModelCoachingSourceReferenceCategory
    let reason: ModelCoachingOmissionReason
}

enum ModelCoachingSourceReferenceCategory: String, Codable, Equatable, Sendable {
    case action
    case boardTask
    case piece
    case move
    case relationship
    case reply
    case tacticalFact
}

enum ModelCoachingOmissionReason: String, Codable, Equatable, Sendable {
    case redundantReply
    case lowerPriorityCandidate
    case unrelatedPiece
    case unrelatedRelationship
    case representedByCompleteSummary
}
