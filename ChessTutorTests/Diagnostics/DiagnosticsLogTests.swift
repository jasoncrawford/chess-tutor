import CloudKit
import XCTest
@testable import ChessTutor

final class DiagnosticsLogTests: XCTestCase {
    func testFormatsEventsWithSortedEscapedFields() async {
        let log = DiagnosticsLog(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            now: { Date(timeIntervalSince1970: 20) }
        )
        let event = DiagnosticsEvent(
            timestamp: Date(timeIntervalSince1970: 10),
            category: "invite",
            name: "fetchFailed",
            fields: [
                "message": "That code did not match",
                "code": "428193"
            ]
        )

        let line = await log.format(event)

        XCTAssertEqual(
            line,
            "1970-01-01T00:00:10.000Z invite.fetchFailed code=428193 message=\"That code did not match\""
        )
    }

    func testAppendAndExportIncludesHeaderAndEvents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let log = DiagnosticsLog(
            directoryURL: directory,
            now: { Date(timeIntervalSince1970: 20) }
        )

        await log.append(
            category: "remoteInvite",
            "created",
            fields: ["code": "428193"],
            timestamp: Date(timeIntervalSince1970: 10)
        )
        let exportText = await log.exportText()

        XCTAssertTrue(exportText.contains("ChessTutor Diagnostics"))
        XCTAssertTrue(exportText.contains("generatedAt=1970-01-01T00:00:20.000Z"))
        XCTAssertTrue(exportText.contains("remoteInvite.created code=428193"))
    }

    func testInstallationIDPersistsForLogDirectory() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let firstLog = DiagnosticsLog(directoryURL: directory)
        let firstID = await firstLog.installationID()
        let secondLog = DiagnosticsLog(directoryURL: directory)

        let secondID = await secondLog.installationID()

        XCTAssertEqual(secondID, firstID)
        XCTAssertFalse(firstID.isEmpty)
    }

    func testExportFileUsesInstallPrefixAndTextExtension() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let log = DiagnosticsLog(
            directoryURL: directory,
            now: { Date(timeIntervalSince1970: 20) }
        )
        let installationID = await log.installationID()

        let exportURL = try await log.exportFile()

        XCTAssertEqual(exportURL.pathExtension, "txt")
        XCTAssertTrue(exportURL.lastPathComponent.contains(String(installationID.prefix(8))))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    }

    func testTokenSuffixDoesNotExposeFullToken() {
        let token = RemoteInviteToken(rawValue: "secret-token-abcdef")

        XCTAssertEqual(DiagnosticsLog.tokenSuffix(token), "abcdef")
        XCTAssertEqual(DiagnosticsLog.tokenSuffix(nil), "none")
    }

    func testCloudKitFieldsIncludeCodeName() {
        let fields = DiagnosticsLog.cloudKitFields(from: CKError(.networkUnavailable))

        XCTAssertEqual(fields["errorType"], "CKError")
        XCTAssertEqual(fields["ckCodeName"], "networkUnavailable")
    }
}
