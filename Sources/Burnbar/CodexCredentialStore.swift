import Foundation

struct CodexCredentialStore {
    let fileURL: URL

    /// Reads one profile-scoped Codex OAuth credential. The caller supplies the
    /// exact profile home, so there is intentionally no label matching or
    /// cross-profile fallback.
    func credential() throws -> CodexCredential? {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        let authStore = try JSONDecoder().decode(AuthStore.self, from: data)
        guard let accessToken = authStore.tokens.accessToken, !accessToken.isEmpty else {
            return nil
        }
        return CodexCredential(accessToken: accessToken, accountID: authStore.tokens.accountID)
    }

    private struct AuthStore: Decodable {
        let tokens: Tokens
    }

    private struct Tokens: Decodable {
        let accessToken: String?
        let accountID: String?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }
}

struct CodexCredential: Sendable {
    let accessToken: String
    let accountID: String?
}
