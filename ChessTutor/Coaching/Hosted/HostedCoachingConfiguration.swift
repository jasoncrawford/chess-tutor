import Foundation
import Security

protocol HostedCoachingCredentialStoring: Sendable {
    func loadConfiguration() throws -> HostedCoachingConfiguration?
    func saveConfiguration(_ configuration: HostedCoachingConfiguration) throws
}

enum HostedCoachingConfigurationError: Error, Equatable, Sendable {
    case invalidBaseURL
    case missingAccessToken
    case credentialStoreFailure
}

struct HostedCoachingConfiguration: Codable, Equatable, Sendable {
    let baseURL: URL
    let accessToken: String

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        credentialStore: any HostedCoachingCredentialStoring = KeychainHostedCoachingCredentialStore(),
        isDebugBuild: Bool = Self.isDebugBuild
    ) throws -> HostedCoachingConfiguration? {
        do {
            guard let rawBaseURL = environment["CHESS_TUTOR_COACHING_BASE_URL"] else {
                guard environment["CHESS_TUTOR_COACHING_ACCESS_TOKEN"] == nil else {
                    throw HostedCoachingConfigurationError.invalidBaseURL
                }
                guard let saved = try credentialStore.loadConfiguration() else { return nil }
                return try validated(saved, isDebugBuild: isDebugBuild)
            }
            let baseURL = try validatedBaseURL(rawBaseURL, isDebugBuild: isDebugBuild)
            if let token = environment["CHESS_TUTOR_COACHING_ACCESS_TOKEN"] {
                let configuration = try validated(
                    Self(baseURL: baseURL, accessToken: token), isDebugBuild: isDebugBuild
                )
                try credentialStore.saveConfiguration(configuration)
                return configuration
            }
            guard let saved = try credentialStore.loadConfiguration() else {
                throw HostedCoachingConfigurationError.missingAccessToken
            }
            let configuration = try validated(saved, isDebugBuild: isDebugBuild)
            guard configuration.baseURL == baseURL else {
                throw HostedCoachingConfigurationError.missingAccessToken
            }
            return configuration
        } catch let error as HostedCoachingConfigurationError {
            throw error
        } catch {
            throw HostedCoachingConfigurationError.credentialStoreFailure
        }
    }

    private static func validated(_ configuration: Self, isDebugBuild: Bool) throws -> Self {
        let token = configuration.accessToken
        guard !token.isEmpty, token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            throw HostedCoachingConfigurationError.missingAccessToken
        }
        return Self(
            baseURL: try validatedBaseURL(configuration.baseURL.absoluteString, isDebugBuild: isDebugBuild),
            accessToken: token
        )
    }

    private static func validatedBaseURL(
        _ value: String,
        isDebugBuild: Bool
    ) throws -> URL {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw HostedCoachingConfigurationError.invalidBaseURL
        }
        guard scheme == "https" || (scheme == "http" && isDebugBuild && isPrivateDevelopmentHost(host)) else {
            throw HostedCoachingConfigurationError.invalidBaseURL
        }
        components.scheme = scheme
        components.host = host
        components.path = ""
        if components.port == (scheme == "https" ? 443 : 80) { components.port = nil }
        guard let url = components.url else { throw HostedCoachingConfigurationError.invalidBaseURL }
        return url
    }

    private static func isPrivateDevelopmentHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host == "[::1]" {
            return true
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }
        return octets[0] == 127 || octets[0] == 10
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 172 && (16...31).contains(octets[1]))
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

struct KeychainHostedCoachingCredentialStore: HostedCoachingCredentialStoring, Sendable {
    let service: String
    let account: String

    init(service: String = "org.jasoncrawford.chesstutor.hosted-coaching", account: String = "connection") {
        self.service = service
        self.account = account
    }

    func loadConfiguration() throws -> HostedCoachingConfiguration? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let configuration = try? JSONDecoder().decode(HostedCoachingConfiguration.self, from: data) else {
            throw HostedCoachingConfigurationError.credentialStoreFailure
        }
        return configuration
    }

    func saveConfiguration(_ configuration: HostedCoachingConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw HostedCoachingConfigurationError.credentialStoreFailure
        }
        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
            throw HostedCoachingConfigurationError.credentialStoreFailure
        }
    }
}

enum HostedCoachingRuntime {
    static func resolveProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        credentialStore: any HostedCoachingCredentialStoring = KeychainHostedCoachingCredentialStore()
    ) -> (any HostedCoachingTurning)? {
        do {
            guard let configuration = try HostedCoachingConfiguration.resolve(
                environment: environment,
                credentialStore: credentialStore
            ) else {
                return nil
            }
            return URLSessionHostedCoachingTransport(
                baseURL: configuration.baseURL,
                accessToken: configuration.accessToken
            )
        } catch {
            return UnavailableHostedCoachingProvider()
        }
    }
}

private struct UnavailableHostedCoachingProvider: HostedCoachingTurning {
    func turn(
        for request: ModelCoachingNeutralRequest,
        contract: ModelCoachingChessNativeResponseContract,
        continuationID: String?,
        correlation: HostedCoachingCorrelation
    ) async throws -> HostedCoachingResponse {
        _ = correlation
        throw HostedCoachingTransportError.serverUnavailable
    }
}
