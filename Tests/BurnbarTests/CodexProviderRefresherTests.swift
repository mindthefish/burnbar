import Foundation
import os
import Testing
@testable import Burnbar

struct CodexProviderRefresherTests {
    @Test
    func backoffSkipsCredentialReadsAndHonorsServerDelayButManualRefreshBypassesIt() async {
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1000))
        let refresher = CodexProviderRefresher(
            read: { _ in
                reads.withLock { $0 += 1 }
                return CodexCredential(accessToken: "fake", accountID: nil)
            },
            fetch: { _ in throw CodexUsageClientError.rateLimited(retryAfter: 7200) },
            now: { clock.withLock { $0 } }
        )
        let url = URL(fileURLWithPath: "/unused/auth.json")
        #expect(await refresher.refresh(authFileURL: url) == .failed(.rateLimited))
        clock.withLock { $0 = Date(timeIntervalSince1970: 4600) }
        #expect(await refresher.refresh(authFileURL: url) == .failed(.rateLimited))
        #expect(reads.withLock { $0 } == 1)
        #expect(await refresher.refresh(authFileURL: url, force: true) == .failed(.rateLimited))
        #expect(reads.withLock { $0 } == 2)
    }

    @Test
    func authenticationFailuresAreNotRetried() async {
        let requests = OSAllocatedUnfairLock(initialState: 0)
        let refresher = CodexProviderRefresher(
            read: { _ in CodexCredential(accessToken: "fake", accountID: nil) },
            fetch: { _ in
                requests.withLock { $0 += 1 }
                throw CodexUsageClientError.unauthorized
            }
        )
        #expect(await refresher.refresh(authFileURL: URL(fileURLWithPath: "/unused")) == .failed(.unauthorized))
        #expect(requests.withLock { $0 } == 1)
    }
}
