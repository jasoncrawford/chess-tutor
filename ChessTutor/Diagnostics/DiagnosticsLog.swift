import CloudKit
import Foundation
import UIKit

struct DiagnosticsEvent: Equatable, Sendable {
    let timestamp: Date
    let category: String
    let name: String
    let fields: [String: String]

    init(
        timestamp: Date = Date(),
        category: String,
        name: String,
        fields: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.category = category
        self.name = name
        self.fields = fields
    }
}

struct DiagnosticsDeviceSnapshot: Equatable, Sendable {
    let installationID: String
    let idiom: String
    let deviceModel: String
    let modelIdentifier: String
    let systemName: String
    let systemVersion: String

    @MainActor
    static func current(installationID: String) -> DiagnosticsDeviceSnapshot {
        let device = UIDevice.current
        return DiagnosticsDeviceSnapshot(
            installationID: installationID,
            idiom: Self.idiomName(device.userInterfaceIdiom),
            deviceModel: device.model,
            modelIdentifier: Self.modelIdentifier(),
            systemName: device.systemName,
            systemVersion: device.systemVersion
        )
    }

    private static func idiomName(_ idiom: UIUserInterfaceIdiom) -> String {
        switch idiom {
        case .phone:
            return "phone"
        case .pad:
            return "pad"
        case .mac:
            return "mac"
        case .tv:
            return "tv"
        case .carPlay:
            return "carPlay"
        case .vision:
            return "vision"
        case .unspecified:
            fallthrough
        @unknown default:
            return "unspecified"
        }
    }

    private static func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { cString in
                String(cString: cString)
            }
        }
    }
}

actor DiagnosticsLog {
    static let shared = DiagnosticsLog()

    private let fileURL: URL
    private let installationIDURL: URL
    private let exportDirectoryURL: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let maxLogBytes: Int
    private let timestampFormatter = ISO8601DateFormatter()

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        maxLogBytes: Int = 512_000
    ) {
        self.fileManager = fileManager
        self.now = now
        self.maxLogBytes = maxLogBytes
        let baseDirectory = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.fileURL = baseDirectory.appendingPathComponent("diagnostics.log")
        self.installationIDURL = baseDirectory.appendingPathComponent("installation-id.txt")
        self.exportDirectoryURL = baseDirectory.appendingPathComponent("Exports", isDirectory: true)
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func append(
        category: String,
        _ name: String,
        fields: [String: String] = [:],
        timestamp: Date? = nil
    ) async {
        let event = DiagnosticsEvent(
            timestamp: timestamp ?? now(),
            category: category,
            name: name,
            fields: fields
        )
        appendLine(format(event))
    }

    func logAppLaunch(
        runtimeMode: RemotePlayRuntimeMode,
        device: DiagnosticsDeviceSnapshot,
        localPlayerID: RemotePlayerID?
    ) async {
        await append(
            category: "app",
            "launch",
            fields: [
                "runtimeMode": "\(runtimeMode)",
                "installationID": device.installationID,
                "idiom": device.idiom,
                "deviceModel": device.deviceModel,
                "modelIdentifier": device.modelIdentifier,
                "system": "\(device.systemName) \(device.systemVersion)",
                "localPlayerID": localPlayerID?.rawValue ?? "none"
            ]
        )
    }

    func installationID() -> String {
        if let existing = try? String(contentsOf: installationIDURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }

        let nextID = UUID().uuidString
        do {
            try fileManager.createDirectory(
                at: installationIDURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try nextID.write(to: installationIDURL, atomically: true, encoding: .utf8)
        } catch {
            return nextID
        }
        return nextID
    }

    func exportText() -> String {
        let body = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        return """
        ChessTutor Diagnostics
        generatedAt=\(timestampFormatter.string(from: now()))
        installationID=\(installationID())

        \(body)
        """
    }

    func exportFile() throws -> URL {
        try fileManager.createDirectory(at: exportDirectoryURL, withIntermediateDirectories: true)
        let timestamp = Self.filenameTimestamp.string(from: now())
        let installPrefix = String(installationID().prefix(8))
        let exportURL = exportDirectoryURL.appendingPathComponent(
            "ChessTutor-Diagnostics-\(installPrefix)-\(timestamp).txt"
        )
        try exportText().write(to: exportURL, atomically: true, encoding: .utf8)
        return exportURL
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }

    func format(_ event: DiagnosticsEvent) -> String {
        var components = [
            timestampFormatter.string(from: event.timestamp),
            "\(event.category).\(event.name)"
        ]
        for key in event.fields.keys.sorted() {
            if let value = event.fields[key] {
                components.append("\(key)=\(Self.escape(value))")
            }
        }
        return components.joined(separator: " ")
    }

    private func appendLine(_ line: String) {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let lineData = Data((line + "\n").utf8)
            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: lineData)
                try handle.close()
            } else {
                try lineData.write(to: fileURL, options: .atomic)
            }
            try trimIfNeeded()
        } catch {
            return
        }
    }

    private func trimIfNeeded() throws {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > maxLogBytes else {
            return
        }

        let data = try Data(contentsOf: fileURL)
        let keepBytes = max(maxLogBytes / 2, 1)
        let suffix = data.suffix(keepBytes)
        let newlineByte = UInt8(ascii: "\n")
        if let newlineIndex = suffix.firstIndex(of: newlineByte) {
            try suffix[(newlineIndex + 1)...].write(to: fileURL, options: .atomic)
        } else {
            try suffix.write(to: fileURL, options: .atomic)
        }
    }

    private static func escape(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")
        if escaped.contains(" ") || escaped.contains("=") || escaped.isEmpty {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static let filenameTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

extension DiagnosticsLog {
    static func tokenSuffix(_ token: RemoteInviteToken?) -> String {
        guard let token else {
            return "none"
        }
        return String(token.rawValue.suffix(6))
    }

    static func cloudKitFields(from error: any Error) -> [String: String] {
        guard let cloudKitError = error as? CKError else {
            return [
                "errorType": String(describing: type(of: error)),
                "error": String(describing: error)
            ]
        }
        var fields: [String: String] = [
            "errorType": "CKError",
            "ckCode": "\(cloudKitError.code.rawValue)",
            "ckCodeName": cloudKitCodeName(cloudKitError.code)
        ]
        if let serverRecord = cloudKitError.serverRecord {
            fields["serverRecord"] = serverRecord.recordID.recordName
        }
        if let retryAfter = cloudKitError.retryAfterSeconds {
            fields["retryAfterSeconds"] = "\(retryAfter)"
        }
        return fields
    }

    private static func cloudKitCodeName(_ code: CKError.Code) -> String {
        switch code {
        case .unknownItem:
            return "unknownItem"
        case .networkUnavailable:
            return "networkUnavailable"
        case .networkFailure:
            return "networkFailure"
        case .notAuthenticated:
            return "notAuthenticated"
        case .permissionFailure:
            return "permissionFailure"
        case .serverRecordChanged:
            return "serverRecordChanged"
        case .quotaExceeded:
            return "quotaExceeded"
        case .requestRateLimited:
            return "requestRateLimited"
        case .serviceUnavailable:
            return "serviceUnavailable"
        case .zoneBusy:
            return "zoneBusy"
        case .partialFailure:
            return "partialFailure"
        case .badContainer:
            return "badContainer"
        case .badDatabase:
            return "badDatabase"
        case .internalError:
            return "internalError"
        case .serverRejectedRequest:
            return "serverRejectedRequest"
        case .invalidArguments:
            return "invalidArguments"
        case .resultsTruncated:
            return "resultsTruncated"
        case .constraintViolation:
            return "constraintViolation"
        case .operationCancelled:
            return "operationCancelled"
        case .changeTokenExpired:
            return "changeTokenExpired"
        case .batchRequestFailed:
            return "batchRequestFailed"
        case .zoneNotFound:
            return "zoneNotFound"
        case .userDeletedZone:
            return "userDeletedZone"
        case .tooManyParticipants:
            return "tooManyParticipants"
        case .alreadyShared:
            return "alreadyShared"
        case .referenceViolation:
            return "referenceViolation"
        case .managedAccountRestricted:
            return "managedAccountRestricted"
        case .participantMayNeedVerification:
            return "participantMayNeedVerification"
        case .serverResponseLost:
            return "serverResponseLost"
        case .assetFileNotFound:
            return "assetFileNotFound"
        case .assetFileModified:
            return "assetFileModified"
        case .incompatibleVersion:
            return "incompatibleVersion"
        case .missingEntitlement:
            return "missingEntitlement"
        case .limitExceeded:
            return "limitExceeded"
        case .assetNotAvailable:
            return "assetNotAvailable"
        case .accountTemporarilyUnavailable:
            return "accountTemporarilyUnavailable"
        case .participantAlreadyInvited:
            return "participantAlreadyInvited"
        @unknown default:
            return "unknown-\(code.rawValue)"
        }
    }
}
