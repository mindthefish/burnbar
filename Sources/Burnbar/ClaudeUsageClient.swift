import Foundation

struct ClaudeUsageClient {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let dataLoader: DataLoader

    init(session: URLSession = UsageNetwork.session) {
        dataLoader = { request in
            try await session.data(for: request)
        }
    }

    init(dataLoader: @escaping DataLoader) {
        self.dataLoader = dataLoader
    }

    func fetch(credential: ClaudeCredential) async throws -> QuotaSnapshot {
        var request = URLRequest(url: Self.usageURL, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        // Identify the client honestly. Requests without a User-Agent are a
        // plausible reason for being throttled harder than a named one.
        request.setValue("Burnbar/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeUsageClientError.invalidResponse
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ClaudeUsageClientError.unauthorized
        }
        if httpResponse.statusCode == 429 {
            throw ClaudeUsageClientError.rateLimited
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClaudeUsageClientError.invalidResponse
        }

        return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data).quotaSnapshot
    }
}

enum ClaudeUsageClientError: Error {
    case invalidResponse
    /// The token was rejected, which happens after Claude Code rotates it.
    case unauthorized
    case rateLimited
}
