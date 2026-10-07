import Foundation
import Testing
@testable import Burnbar

struct ClaudeProviderRefresherTests {
    private let snapshot = QuotaSnapshot(
        state: .available,
        windows: [QuotaWindow(label: "5h", usedPercentage: 21, resetsAt: Date(timeIntervalSince1970: 0))]
    )

    @Test
    func readsTheKeychainOnceAcrossRepeatedRefreshes() async {
        let reads = Counter()
        let refresher = ClaudeProviderRefresher(
            credentialReader: {
                reads.increment()
                return .found(ClaudeCredential(accessToken: "token"), source: .keychain)
            },
            fetch: { _ in self.snapshot }
        )

        _ = await refresher.refresh()
        _ = await refresher.refresh()
        _ = await refresher.refresh()

        #expect(reads.value == 1)
    }

    @Test
    func rereadsTheKeychainAfterTheTokenIsRejected() async {
        let reads = Counter()
        let attempts = Counter()
        let refresher = ClaudeProviderRefresher(
            credentialReader: {
                reads.increment()
                return .found(ClaudeCredential(accessToken: "token-\(reads.value)"), source: .keychain)
            },
            fetch: { _ in
                attempts.increment()
                if attempts.value == 1 {
                    throw ClaudeUsageClientError.unauthorized
                }
                return self.snapshot
            }
        )

        let result = await refresher.refresh()

        #expect(reads.value == 2)
        #expect(result.snapshot == snapshot)
        #expect(result.failure == nil)
    }

    @Test
    func doesNotRetryAnUnchangedRejectedTokenOrKeepItCached() async {
        let reads = Counter()
        let attempts = Counter()
        let refresher = ClaudeProviderRefresher(
            credentialReader: {
                reads.increment()
                return .found(ClaudeCredential(accessToken: "rejected"), source: .keychain)
            },
            fetch: { _ in
                attempts.increment()
                throw ClaudeUsageClientError.unauthorized
            }
        )

        #expect(await refresher.refresh().failure == .unauthorized)
        #expect(await refresher.refresh().failure == .unauthorized)
        #expect(attempts.value == 2)
        #expect(reads.value == 4)
    }

    @Test
    func clearsAReplacementCredentialRejectedByTheFinalAttempt() async {
        let reads = Counter()
        let attempts = Counter()
        let refresher = ClaudeProviderRefresher(
            credentialReader: {
                reads.increment()
                return .found(ClaudeCredential(accessToken: "token-\(reads.value)"), source: .keychain)
            },
            fetch: { _ in
                attempts.increment()
                if attempts.value <= 2 {
                    throw ClaudeUsageClientError.unauthorized
                }
                return self.snapshot
            }
        )

        #expect(await refresher.refresh().failure == .unauthorized)
        #expect(await refresher.refresh().snapshot == snapshot)
        #expect(attempts.value == 3)
        #expect(reads.value == 3)
    }

    @Test
    func checksForAFileCredentialWhileUsingACachedKeychainCredential() async {
        let reads = Counter()
        let fileReads = Counter()
        let fileAvailable = Flag()
        let refresher = ClaudeProviderRefresher(
            credentialReader: {
                reads.increment()
                return .found(ClaudeCredential(accessToken: "old-keychain"), source: .keychain)
            },
            fileCredentialReader: {
                fileReads.increment()
                return fileAvailable.isSet ? ClaudeCredential(accessToken: "new-file") : nil
            },
            fetch: { credential in
                #expect(credential.accessToken == (fileAvailable.isSet ? "new-file" : "old-keychain"))
                return self.snapshot
            }
        )

        _ = await refresher.refresh()
        _ = await refresher.refresh(force: true)
        fileAvailable.set()
        #expect(await refresher.refresh().snapshot == snapshot)
        #expect(reads.value == 1)
        #expect(fileReads.value == 2)
    }

    @Test
    func keepsTheCachedKeychainFallbackWhenTheFileTokenHasExpired() async {
        let reads = Counter()
        let clock = Clock(now: Date(timeIntervalSince1970: 1_000))
        let refresher = ClaudeProviderRefresher(
            credentialReader: {
                reads.increment()
                return .found(ClaudeCredential(accessToken: "keychain"), source: .keychain)
            },
            fileCredentialReader: {
                ClaudeCredential(accessToken: "expired-file", expiresAt: Date(timeIntervalSince1970: 999))
            },
            fetch: { credential in
                #expect(credential.accessToken == "keychain")
                return self.snapshot
            },
            now: { clock.now }
        )

        _ = await refresher.refresh()
        #expect(await refresher.refresh().snapshot == snapshot)
        #expect(reads.value == 1)
    }

    @Test
    func explicitAuthorizationChecksTheSourceAgainDespiteAValidCache() async {
        let permissions = PermissionRecorder()
        let refresher = ClaudeProviderRefresher(
            credentialReader: { allowInteraction in
                permissions.append(allowInteraction)
                return .found(
                    ClaudeCredential(accessToken: allowInteraction ? "current-keychain" : "old-keychain"),
                    source: .keychain
                )
            },
            fetch: { credential in
                #expect(credential.accessToken == (permissions.values.last == true ? "current-keychain" : "old-keychain"))
                return self.snapshot
            }
        )

        _ = await refresher.refresh()
        #expect(await refresher.refresh(force: true, allowInteraction: true).snapshot == snapshot)
        #expect(permissions.values == [false, true])
    }

    @Test
    func reportsUnavailableWithoutAUsableCredential() async {
        let refresher = ClaudeProviderRefresher(
            credentialReader: { .found(ClaudeCredential(accessToken: ""), source: .keychain) },
            fetch: { _ in
                Issue.record("must not fetch without a credential")
                return .unavailable
            }
        )

        let result = await refresher.refresh()

        #expect(result.snapshot == .unavailable)
        #expect(result.failure == .noCredential)
    }

    @Test
    func keepsTheCredentialWhenAFetchFailsForOtherReasons() async {
        let reads = Counter()
        let refresher = ClaudeProviderRefresher(
            credentialReader: {
                reads.increment()
                return .found(ClaudeCredential(accessToken: "token"), source: .keychain)
            },
            fetch: { _ in throw ClaudeUsageClientError.invalidResponse }
        )

        _ = await refresher.refresh()
        let result = await refresher.refresh()

        #expect(reads.value == 1)
        #expect(result.failure == .unexpectedResponse)
    }

    @Test
    func reportsBeingOfflineForConnectionErrors() async {
        let refresher = ClaudeProviderRefresher(
            credentialReader: { .found(ClaudeCredential(accessToken: "token"), source: .keychain) },
            fetch: { _ in throw URLError(.notConnectedToInternet) }
        )

        #expect(await refresher.refresh().failure == .offline)
    }

    @Test
    func skipsScheduledFetchesWhileBackingOffFromARateLimit() async {
        let fetches = Counter()
        let clock = Clock(now: Date(timeIntervalSince1970: 0))
        let refresher = ClaudeProviderRefresher(
            credentialReader: { .found(ClaudeCredential(accessToken: "token"), source: .keychain) },
            fetch: { _ in
                fetches.increment()
                throw ClaudeUsageClientError.rateLimited
            },
            now: { clock.now }
        )

        _ = await refresher.refresh(force: false)
        #expect(fetches.value == 1)

        clock.advance(by: 5 * 60)
        let blocked = await refresher.refresh(force: false)

        #expect(fetches.value == 1)
        #expect(blocked.failure == .rateLimited)
    }

    @Test
    func aManualRefreshBypassesTheBackoff() async {
        let fetches = Counter()
        let clock = Clock(now: Date(timeIntervalSince1970: 0))
        let refresher = ClaudeProviderRefresher(
            credentialReader: { .found(ClaudeCredential(accessToken: "token"), source: .keychain) },
            fetch: { _ in
                fetches.increment()
                throw ClaudeUsageClientError.rateLimited
            },
            now: { clock.now }
        )

        _ = await refresher.refresh(force: false)
        _ = await refresher.refresh(force: true)

        #expect(fetches.value == 2)
    }

    @Test
    func resumesTheNormalScheduleAfterASuccessfulFetch() async {
        let clock = Clock(now: Date(timeIntervalSince1970: 0))
        let succeed = Flag()
        let refresher = ClaudeProviderRefresher(
            credentialReader: { .found(ClaudeCredential(accessToken: "token"), source: .keychain) },
            fetch: { _ in
                if succeed.isSet {
                    return self.snapshot
                }
                throw ClaudeUsageClientError.rateLimited
            },
            now: { clock.now }
        )

        _ = await refresher.refresh(force: false)
        succeed.set()
        _ = await refresher.refresh(force: true)

        clock.advance(by: 60)
        let result = await refresher.refresh(force: false)

        #expect(result.snapshot == snapshot)
        #expect(result.failure == nil)
    }
    @Test
    func reportsARefusedKeychainReadDistinctlyFromAMissingItem() async {
        let denied = ClaudeProviderRefresher(
            credentialReader: { .accessDenied(errSecAuthFailed) },
            fetch: { _ in
                Issue.record("must not fetch without a credential")
                return .unavailable
            }
        )
        let missing = ClaudeProviderRefresher(
            credentialReader: { .itemNotFound },
            fetch: { _ in
                Issue.record("must not fetch without a credential")
                return .unavailable
            }
        )

        #expect(await denied.refresh().failure == .keychainDenied(errSecAuthFailed))
        #expect(await missing.refresh().failure == .noCredential)
    }

    @Test
    func reportsTheFieldNamesWhenTheCredentialCannotBeParsed() async {
        let refresher = ClaudeProviderRefresher(
            credentialReader: { .unreadable(topLevelKeys: ["someNewShape"], byteCount: 42, isText: true) },
            fetch: { _ in
                Issue.record("must not fetch without a credential")
                return .unavailable
            }
        )

        #expect(await refresher.refresh().failure == .unreadableCredential(
            topLevelKeys: ["someNewShape"],
            byteCount: 42,
            isText: true
        ))
    }

    @Test
    func doesNotSpendARequestOnAnExpiredToken() async {
        let clock = Clock(now: Date(timeIntervalSince1970: 1_000))
        let refresher = ClaudeProviderRefresher(
            credentialReader: {
                .found(
                    ClaudeCredential(
                        accessToken: "token",
                        expiresAt: Date(timeIntervalSince1970: 999)
                    ),
                    source: .file
                )
            },
            fetch: { _ in
                Issue.record("must not send an expired token")
                return .unavailable
            },
            now: { clock.now }
        )

        #expect(await refresher.refresh().failure == .tokenExpired)
    }

    @Test
    func rereadsAfterAnExpiredCachedKeychainTokenAndUsesTheFreshFileToken() async {
        let reads = Counter()
        let clock = Clock(now: Date(timeIntervalSince1970: 1_000))
        let refresher = ClaudeProviderRefresher(
            credentialReader: {
                reads.increment()
                if reads.value == 1 {
                    return .found(
                        ClaudeCredential(
                            accessToken: "expired-keychain-token",
                            expiresAt: Date(timeIntervalSince1970: 999)
                        ),
                        source: .keychain
                    )
                }
                return .found(
                    ClaudeCredential(
                        accessToken: "fresh-file-token",
                        expiresAt: Date(timeIntervalSince1970: 2_000)
                    ),
                    source: .file
                )
            },
            fetch: { credential in
                #expect(credential.accessToken == "fresh-file-token")
                return self.snapshot
            },
            now: { clock.now }
        )

        let result = await refresher.refresh()

        #expect(reads.value == 2)
        #expect(result.snapshot == snapshot)
        #expect(result.failure == nil)
    }

    @Test
    func rereadsTheFileEveryTimeSoARotatedTokenIsPickedUp() async {
        let reads = Counter()
        let refresher = ClaudeProviderRefresher(
            credentialReader: {
                reads.increment()
                return .found(ClaudeCredential(accessToken: "token"), source: .file)
            },
            fetch: { _ in self.snapshot }
        )

        _ = await refresher.refresh()
        _ = await refresher.refresh()

        #expect(reads.value == 2)
    }

    @Test
    func passesKeychainInteractionPermissionThroughToTheCredentialReader() async {
        let permissions = PermissionRecorder()
        let refresher = ClaudeProviderRefresher(
            credentialReader: { allowInteraction in
                permissions.append(allowInteraction)
                return .itemNotFound
            },
            fetch: { _ in
                Issue.record("must not fetch without a credential")
                return .unavailable
            }
        )

        _ = await refresher.refresh()
        _ = await refresher.refresh(force: true, allowInteraction: true)

        #expect(permissions.values == [false, true])
    }

}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(now: Date) {
        current = now
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.withLock { value }
    }

    func set() {
        lock.withLock { value = true }
    }
}

private final class PermissionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Bool] = []

    var values: [Bool] {
        lock.withLock { recorded }
    }

    func append(_ value: Bool) {
        lock.withLock { recorded.append(value) }
    }
}
