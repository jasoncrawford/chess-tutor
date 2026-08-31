import Foundation
import Security

protocol HostedCoachingCredentialStoring: Sendable {
    func loadAccessToken() throws -> String?
    func saveAccessToken(_ token: String) throws
}

enum HostedCoachingConfigurationError: Error, Equatable, Sendable {
    case invalidBaseURL
    case missingAccessToken
    case credentialStoreFailure
}

struct HostedCoachingConfiguration: Equatable, Sendable {
    let baseURL: URL
    let accessToken: String

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        credentialStore: any HostedCoachingCredentialStoring = KeychainHostedCoachingCredentialStore(),
        isDebugBuild: Bool = Self.isDebugBuild
    ) throws -> HostedCoachingConfiguration? {
        guard let rawBaseURL = environment["CHESS_TUTOR_COACHING_BASE_URL"],
              !rawBaseURL.isEmpty else {
            return nil
        }
        let baseURL = try validatedBaseURL(rawBaseURL, isDebugBuild: isDebugBuild)

        if let launchToken = environment["CHESS_TUTOR_COACHING_ACCESS_TOKEN"],
           !launchToken.isEmpty {
            do {
                try credentialStore.saveAccessToken(launchToken)
            } catch {
                throw HostedCoachingConfigurationError.credentialStoreFailure
            }
        }
        let token: String?
        do {
            token = try credentialStore.loadAccessToken()
        } catch {
            throw HostedCoachingConfigurationError.credentialStoreFailure
        }
        guard let token, !token.isEmpty else {
            throw HostedCoachingConfigurationError.missingAccessToken
        }
        return HostedCoachingConfiguration(baseURL: baseURL, accessToken: token)
    }

    private static func validatedBaseURL(
        _ value: String,
        isDebugBuild: Bool
    ) throws -> URL {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let url = components.url else {
            throw HostedCoachingConfigurationError.invalidBaseURL
        }
        if scheme == "https" {
            return url
        }
        guard scheme == "http", isDebugBuild, isPrivateDevelopmentHost(host) else {
            throw HostedCoachingConfigurationError.invalidBaseURL
        }
        return url
    }

    private static func isPrivateDevelopmentHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host.hasPrefix("127.") {
            return true
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }
        return octets[0] == 10
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
    private let service = "org.jasoncrawford.chesstutor.hosted-coaching"
    private let account = "access-token"

    func loadAccessToken() throws -> String? {
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
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw HostedCoachingConfigurationError.credentialStoreFailure
        }
        return token
    }

    func saveAccessToken(_ token: String) throws {
        guard !token.isEmpty, let data = token.data(using: .utf8) else {
            throw HostedCoachingConfigurationError.credentialStoreFailure
        }
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
        guard environment["CHESS_TUTOR_COACHING_BASE_URL"]?.isEmpty == false else {
            return nil
        }
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
        continuationID: String?
    ) async throws -> HostedCoachingResponse {
        throw HostedCoachingTransportError.serverUnavailable
    }
}
