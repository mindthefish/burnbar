import Foundation
import Testing
@testable import Burnbar

struct ClaudeUsageClientTests {
    private let body = """
    {
      "five_hour": { "utilization": 21, "resets_at": "2026-08-22T02:00:00Z" }
    }
    """.data(using: .utf8)!

    @Test
    func sendsTheCredentialOnlyToTheAnthropicUsageEndpoint() async throws {
        let recorded = RecordedRequest()
        let client = ClaudeUsageClient { request in
            recorded.store(request)
            return (self.body, HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        _ = try await client.fetch(credential: ClaudeCredential(accessToken: "secret"))

        let request = try #require(recorded.value)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Burnbar/1.0")
    }

    @Test
    func reportsRateLimitingSeparatelyFromOtherFailures() async {
        let client = ClaudeUsageClient { request in
            (Data(), HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        await #expect(throws: ClaudeUsageClientError.rateLimited) {
            _ = try await client.fetch(credential: ClaudeCredential(accessToken: "secret"))
        }
    }

    @Test
    func reportsARejectedToken() async {
        let client = ClaudeUsageClient { request in
            (Data(), HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        await #expect(throws: ClaudeUsageClientError.unauthorized) {
            _ = try await client.fetch(credential: ClaudeCredential(accessToken: "secret"))
        }
    }
}

private final class RecordedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    var value: URLRequest? {
        lock.withLock { request }
    }

    func store(_ request: URLRequest) {
        lock.withLock { self.request = request }
    }
}
