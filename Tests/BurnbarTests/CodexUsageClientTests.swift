import Foundation
import Testing
@testable import Burnbar

struct CodexUsageClientTests {
    @Test(arguments: ["7200", "garbage", "-1"])
    func rateLimitCarriesOnlyValidRetryDelay(header: String) async {
        let client = CodexUsageClient { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": header])!)
        }
        await #expect(throws: CodexUsageClientError.rateLimited(retryAfter: header == "7200" ? 7200 : nil)) {
            try await client.fetch(credential: CodexCredential(accessToken: "fake", accountID: nil))
        }
    }

    @Test(arguments: [401, 403])
    func rejectedTokenHasAnAuthenticationError(status: Int) async {
        let client = CodexUsageClient { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: CodexUsageClientError.unauthorized) {
            try await client.fetch(credential: CodexCredential(accessToken: "fake", accountID: nil))
        }
    }

    @Test
    func sendsCredentialOnlyToTheCodexUsageEndpoint() async throws {
        let recorder = RequestRecorder()
        let responseData = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 42,
              "limit_window_seconds": 18000,
              "reset_at": 1725000000
            }
          }
        }
        """.data(using: .utf8)!
        let client = CodexUsageClient { request in
            await recorder.record(request)
            return (
                responseData,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }

        let snapshot = try await client.fetch(credential: CodexCredential(
            accessToken: "test-private-token",
            accountID: "private-account"
        ))

        let request = await recorder.request
        #expect(request?.url == URL(string: "https://chatgpt.com/backend-api/wham/usage"))
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-private-token")
        #expect(request?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "private-account")
        #expect(snapshot.state == .available)
    }

    @Test
    func omitsTheOptionalAccountHeaderWhenTheCredentialHasNoAccountID() async throws {
        let recorder = RequestRecorder()
        let responseData = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 42,
              "limit_window_seconds": 18000,
              "reset_at": 1725000000
            }
          }
        }
        """.data(using: .utf8)!
        let client = CodexUsageClient { request in
            await recorder.record(request)
            return (
                responseData,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }

        _ = try await client.fetch(credential: CodexCredential(
            accessToken: "test-private-token",
            accountID: nil
        ))

        let request = await recorder.request
        #expect(request?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}
