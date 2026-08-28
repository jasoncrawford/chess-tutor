import CryptoKit
import XCTest
@testable import ChessTutor

final class ModelCoachingCorpusExportTests: XCTestCase {
    func testCorpusArtifactsAreDeterministicAndOptionallyWriteConfiguredOutput() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = configuredValue("COACHING_EVAL_OUTPUT_DIR", in: environment) else {
            let first = try ModelCoachingCorpusExporter.artifacts(sourceGitSHA: "determinism-source")
            let second = try ModelCoachingCorpusExporter.artifacts(sourceGitSHA: "determinism-source")
            XCTAssertEqual(first, second)
            return
        }
        let sourceSHA = try XCTUnwrap(configuredValue("COACHING_EVAL_SOURCE_SHA", in: environment))
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        try ModelCoachingCorpusExporter.write(to: outputURL, sourceGitSHA: sourceSHA)

        XCTAssertEqual(
            try Set(FileManager.default.contentsOfDirectory(atPath: outputPath)),
            ["visible.jsonl", "hidden.jsonl", "corpus-manifest.json"]
        )
        let visibleData = try Data(contentsOf: outputURL.appendingPathComponent("visible.jsonl"))
        let hiddenData = try Data(contentsOf: outputURL.appendingPathComponent("hidden.jsonl"))
        let visibleCases = try decodeCases(from: visibleData)
        let hiddenCases = try decodeCases(from: hiddenData)
        XCTAssertEqual(visibleCases.count, 41)
        XCTAssertEqual(hiddenCases.count, 11)

        let manifestData = try Data(contentsOf: outputURL.appendingPathComponent("corpus-manifest.json"))
        let manifest = try JSONDecoder().decode(ModelCoachingCorpusManifest.self, from: manifestData)
        XCTAssertEqual(manifest.schemaVersion, "model-coaching-corpus-manifest.v1")
        XCTAssertEqual(manifest.corpusSchemaVersion, "model-coaching-evaluation-case.v1")
        XCTAssertEqual(manifest.requestSchemaVersion, "model-coaching-request.v1")
        XCTAssertEqual(manifest.promptVersion, "tutor-v1")
        XCTAssertEqual(manifest.sourceGitSHA, sourceSHA)
        XCTAssertEqual(manifest.caseCount, 52)
        XCTAssertEqual(manifest.visibleCaseCount, 41)
        XCTAssertEqual(manifest.hiddenCaseCount, 11)
        XCTAssertEqual(manifest.visibleCaseIDs, visibleCases.map(\.id))
        XCTAssertEqual(manifest.hiddenCaseIDs, hiddenCases.map(\.id))
        XCTAssertEqual(manifest.visibleSHA256, sha256(visibleData))
        XCTAssertEqual(manifest.hiddenSHA256, sha256(hiddenData))
    }

    func testExporterRefusesToOverwriteNonemptyDirectory() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-coaching-export-nonempty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try Data("keep".utf8).write(to: outputURL.appendingPathComponent("existing.txt"))

        XCTAssertThrowsError(
            try ModelCoachingCorpusExporter.write(to: outputURL, sourceGitSHA: "source")
        ) { error in
            XCTAssertEqual(error as? ModelCoachingCorpusExportError, .nonemptyOutputDirectory)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputURL.path), ["existing.txt"])
    }

    private func configuredValue(_ key: String, in environment: [String: String]) -> String? {
        guard let value = environment[key], !value.isEmpty, !value.hasPrefix("$(") else {
            return nil
        }
        return value
    }

    private func decodeCases(from data: Data) throws -> [ModelCoachingEvaluationCase] {
        try String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(ModelCoachingEvaluationCase.self, from: Data($0.utf8)) }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct ModelCoachingCorpusManifest: Codable, Equatable {
    let schemaVersion: String
    let corpusSchemaVersion: String
    let requestSchemaVersion: String
    let promptVersion: String
    let sourceGitSHA: String
    let caseCount: Int
    let visibleCaseCount: Int
    let hiddenCaseCount: Int
    let visibleCaseIDs: [String]
    let hiddenCaseIDs: [String]
    let visibleSHA256: String
    let hiddenSHA256: String
}

enum ModelCoachingCorpusExportError: Error, Equatable {
    case nonemptyOutputDirectory
    case outputPathIsNotDirectory
    case inconsistentSchemaVersions
}

struct ModelCoachingCorpusArtifacts: Equatable {
    let visibleJSONL: Data
    let hiddenJSONL: Data
    let manifestJSON: Data
}

enum ModelCoachingCorpusExporter {
    static func artifacts(sourceGitSHA: String) throws -> ModelCoachingCorpusArtifacts {
        let allCases = ModelCoachingEvaluationCorpus.allCases
        let visibleCases = allCases.filter { $0.split == .visible }
        let hiddenCases = allCases.filter { $0.split == .hidden }
        let requestSchemaVersions = Set(allCases.map(\.request.schemaVersion))
        let promptVersions = Set(allCases.map(\.request.promptVersion))
        guard requestSchemaVersions.count == 1,
              promptVersions.count == 1,
              let requestSchemaVersion = requestSchemaVersions.first,
              let promptVersion = promptVersions.first else {
            throw ModelCoachingCorpusExportError.inconsistentSchemaVersions
        }

        let visibleJSONL = try jsonl(for: visibleCases)
        let hiddenJSONL = try jsonl(for: hiddenCases)
        let manifest = ModelCoachingCorpusManifest(
            schemaVersion: "model-coaching-corpus-manifest.v1",
            corpusSchemaVersion: "model-coaching-evaluation-case.v1",
            requestSchemaVersion: requestSchemaVersion,
            promptVersion: promptVersion,
            sourceGitSHA: sourceGitSHA,
            caseCount: allCases.count,
            visibleCaseCount: visibleCases.count,
            hiddenCaseCount: hiddenCases.count,
            visibleCaseIDs: visibleCases.map(\.id),
            hiddenCaseIDs: hiddenCases.map(\.id),
            visibleSHA256: sha256(visibleJSONL),
            hiddenSHA256: sha256(hiddenJSONL)
        )
        var manifestJSON = try encoder.encode(manifest)
        manifestJSON.append(0x0A)

        return ModelCoachingCorpusArtifacts(
            visibleJSONL: visibleJSONL,
            hiddenJSONL: hiddenJSONL,
            manifestJSON: manifestJSON
        )
    }

    static func write(to outputURL: URL, sourceGitSHA: String) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ModelCoachingCorpusExportError.outputPathIsNotDirectory
            }
            guard try fileManager.contentsOfDirectory(atPath: outputURL.path).isEmpty else {
                throw ModelCoachingCorpusExportError.nonemptyOutputDirectory
            }
        } else {
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
        }

        let artifacts = try artifacts(sourceGitSHA: sourceGitSHA)
        try artifacts.visibleJSONL.write(to: outputURL.appendingPathComponent("visible.jsonl"), options: .atomic)
        try artifacts.hiddenJSONL.write(to: outputURL.appendingPathComponent("hidden.jsonl"), options: .atomic)
        try artifacts.manifestJSON.write(
            to: outputURL.appendingPathComponent("corpus-manifest.json"),
            options: .atomic
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static func jsonl(for cases: [ModelCoachingEvaluationCase]) throws -> Data {
        var result = Data()
        for evaluationCase in cases {
            result.append(try encoder.encode(evaluationCase))
            result.append(0x0A)
        }
        return result
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
