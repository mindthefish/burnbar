import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct ClaudeCredentialStore {
    /// Why no credential could be produced. Distinguishes a refused Keychain
    /// read from an item whose contents we cannot parse — the two need very
    /// different fixes.
    /// Where a credential came from. The file is cheap to re-read and is
    /// rewritten by Claude Code on every rotation; the Keychain is the one that
    /// costs an access prompt.
    enum Source {
        case file
        case keychain
    }

    enum Outcome {
        case found(ClaudeCredential, source: Source)
        case itemNotFound
        case accessDenied(OSStatus)
        case unreadable(topLevelKeys: [String], byteCount: Int, isText: Bool)
    }

    typealias KeychainLookup = @Sendable (String, Bool) -> (data: Data?, status: OSStatus)
    typealias LegacyKeychainLookup = @Sendable (String) -> (data: Data?, status: OSStatus)
    typealias FileReader = @Sendable (URL) -> Data?

    static let defaultCredentialDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude", isDirectory: true)
    static let defaultCredentialFile = defaultCredentialDirectory
        .appendingPathComponent(".credentials.json")

    /// Claude Code scopes custom configuration directories to a distinct
    /// Keychain service using the first eight hexadecimal SHA-256 characters
    /// of the NFC-normalized directory path.
    static func keychainService(for home: URL) -> String {
        let defaultPath = defaultCredentialDirectory.path
        let path = home.path
        guard path != defaultPath else {
            return "Claude Code-credentials"
        }

        let normalizedPath = path.precomposedStringWithCanonicalMapping
        let digest = SHA256.hash(data: Data(normalizedPath.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(suffix)"
    }

    private let keychainLookup: KeychainLookup
    private let fileReader: FileReader
    private let credentialFile: URL
    private let keychainService: String

    init(
        home: URL = defaultCredentialDirectory,
        keychainLookup: @escaping KeychainLookup = defaultLookup,
        fileReader: @escaping FileReader = { try? Data(contentsOf: $0) },
        credentialFile: URL? = nil
    ) {
        self.keychainLookup = keychainLookup
        self.fileReader = fileReader
        self.credentialFile = credentialFile ?? home.appendingPathComponent(".credentials.json")
        self.keychainService = Self.keychainService(for: home)
    }

    init(
        keychainLookup: @escaping LegacyKeychainLookup,
        fileReader: @escaping FileReader = { try? Data(contentsOf: $0) },
        credentialFile: URL = defaultCredentialFile
    ) {
        self.init(
            home: credentialFile.deletingLastPathComponent(),
            keychainLookup: { service, _ in keychainLookup(service) },
            fileReader: fileReader,
            credentialFile: credentialFile
        )
    }

    func credential(allowInteraction: Bool = false) -> ClaudeCredential? {
        guard case let .found(credential, _) = lookup(allowInteraction: allowInteraction) else {
            return nil
        }
        return credential
    }

    func lookup(allowInteraction: Bool = false) -> Outcome {
        let fileCredential = credentialFromFile()
        if let fileCredential, !fileCredential.hasExpired(at: .now) {
            return .found(fileCredential, source: .file)
        }

        let result = keychainLookup(keychainService, allowInteraction)

        guard let data = result.data else {
            if result.status != errSecItemNotFound, result.status != errSecSuccess {
                return .accessDenied(result.status)
            }
            if let fileCredential {
                return .found(fileCredential, source: .file)
            }
            return result.status == errSecItemNotFound
                ? .itemNotFound
                : .accessDenied(result.status)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let token = Self.accessToken(in: json) {
                let credential = ClaudeCredential(accessToken: token, expiresAt: Self.expiry(in: json))
                if !credential.hasExpired(at: .now) || fileCredential == nil {
                    return .found(credential, source: .keychain)
                }
            }

            if let fileCredential {
                return .found(fileCredential, source: .file)
            }

            return .unreadable(
                topLevelKeys: Self.describe(json),
                byteCount: data.count,
                isText: true
            )
        }

        if let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty, !token.hasPrefix("{") {
            return .found(ClaudeCredential(accessToken: token), source: .keychain)
        }

        if let fileCredential {
            return .found(fileCredential, source: .file)
        }

        let isText = String(data: data, encoding: .utf8) != nil
        return .unreadable(topLevelKeys: [], byteCount: data.count, isText: isText)
    }

    /// Reads only the noninteractive file source, allowing a refresher to check
    /// for a rotation before falling back to its cached Keychain credential.
    func credentialFromFile() -> ClaudeCredential? {
        guard let data = fileReader(credentialFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = Self.accessToken(in: json) else {
            return nil
        }

        return ClaudeCredential(accessToken: token, expiresAt: Self.expiry(in: json))
    }

    /// `expiresAt` is milliseconds since the epoch, nested beside the token.
    private static func expiry(in object: [String: Any], depth: Int = 0) -> Date? {
        if let milliseconds = object["expiresAt"] as? Double {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }

        guard depth < 3 else {
            return nil
        }

        for value in object.values {
            if let nested = value as? [String: Any],
               let expiry = expiry(in: nested, depth: depth + 1) {
                return expiry
            }
        }

        return nil
    }

    /// Access-token field names, matched exactly so a refresh token is never
    /// mistaken for an access token.
    private static let tokenFields = ["accessToken", "access_token", "oauthAccessToken", "oauth_access_token"]

    /// Searches nested objects, because the token has moved between shapes
    /// before and a fixed path breaks silently when it moves again.
    private static func accessToken(in object: [String: Any], depth: Int = 0) -> String? {
        for field in tokenFields {
            if let token = object[field] as? String, !token.isEmpty {
                return token
            }
        }

        guard depth < 3 else {
            return nil
        }

        for value in object.values {
            if let nested = value as? [String: Any],
               let token = accessToken(in: nested, depth: depth + 1) {
                return token
            }
        }

        return nil
    }

    /// Names, types and lengths only, never values. Kept short so it fits the
    /// popover: report what is wrong with the token field rather than listing
    /// every field in the item.
    private static func describe(_ json: [String: Any]) -> [String] {
        guard let oauth = json["claudeAiOauth"] as? [String: Any] else {
            if let value = json["claudeAiOauth"] {
                return ["claudeAiOauth is \(type(of: value))"]
            }
            return json.keys.sorted()
        }

        guard let token = oauth["accessToken"], !(token is NSNull) else {
            return [Self.signedOutDescription]
        }
        if let text = token as? String {
            return text.isEmpty
                ? [Self.signedOutDescription]
                : ["accessToken \(text.count) chars"]
        }
        return ["accessToken is \(type(of: token))"]
    }

    /// An absent or empty access token means Claude Code holds no usable
    /// session, which is what the user needs to know — not the field name.
    static let signedOutDescription = "Claude Code signed out"

    static let defaultLookup: KeychainLookup = { service, allowInteraction in
        let authenticationContext = LAContext()
        authenticationContext.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authenticationContext
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (result as? Data, status)
    }
}

struct ClaudeCredential: Sendable {
    let accessToken: String
    let expiresAt: Date?

    init(accessToken: String, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    var isUsable: Bool { !accessToken.isEmpty }

    /// Sending an expired token only earns an error, so skip the request.
    func hasExpired(at now: Date) -> Bool {
        guard let expiresAt else {
            return false
        }
        return expiresAt <= now
    }
}
