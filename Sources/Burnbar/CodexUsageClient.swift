import Foundation

struct CodexUsageClient {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let dataLoader: DataLoader

    init(session: URLSession = UsageNetwork.session) {
        dataLoader = { request in
            try await session.data(for: request)
        }
    }

    init(dataLoader: @escaping DataLoader) {
        self.dataLoader = dataLoader
    }

    func fetch(credential: CodexCredential) async throws -> QuotaSnapshot {
        var request = URLRequest(url: Self.usageURL, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = credential.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            if let status = (response as? HTTPURLResponse)?.statusCode, status == 401 || status == 403 {
                throw CodexUsageClientError.unauthorized
            }
            if (response as? HTTPURLResponse)?.statusCode == 429 {
                throw CodexUsageClientError.rateLimited(retryAfter: Self.retryDelay(httpResponse: response as? HTTPURLResponse))
            }
            throw CodexUsageClientError.invalidResponse
        }

        return try JSONDecoder().decode(CodexUsageResponse.self, from: data).quotaSnapshot
    }
    private static func retryDelay(httpResponse: HTTPURLResponse?) -> TimeInterval? {
        guard let value = httpResponse?.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}

enum CodexUsageClientError: Error, Equatable {
    case rateLimited(retryAfter: TimeInterval? = nil)
    case unauthorized
    case invalidResponse
}
