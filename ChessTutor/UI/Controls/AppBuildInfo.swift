import Foundation

struct AppBuildInfo: Equatable, Sendable {
    let version: String
    let build: String
    let revision: String?

    var versionDisplayText: String {
        "Version \(version) (Build \(build))"
    }

    var revisionDisplayText: String {
        guard let revision else {
            return "Revision Unknown"
        }
        return "Revision \(revision)"
    }

    static func current(bundle: Bundle = .main) -> AppBuildInfo {
        let infoDictionary = bundle.infoDictionary ?? [:]
        return AppBuildInfo(
            version: normalized(infoDictionary["CFBundleShortVersionString"] as? String) ?? "Unknown",
            build: normalized(infoDictionary["CFBundleVersion"] as? String) ?? "Unknown",
            revision: bundledRevision(in: bundle)
        )
    }

    private static func bundledRevision(in bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "BuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = propertyList as? [String: Any]
        else {
            return nil
        }

        return normalized(dictionary["GitCommit"] as? String)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "unknown"
        else {
            return nil
        }
        return trimmed
    }
}
