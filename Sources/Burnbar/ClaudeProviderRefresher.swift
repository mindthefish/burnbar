import Foundation

/// Fetches the Claude Code quota, holding the credential in memory for the
/// lifetime of the process.
///
/// The Keychain item belongs to Claude Code. Background refreshes explicitly
/// forbid Keychain UI, while a user-initiated refresh may request it. The token
/// is never written anywhere; it is dropped as soon as it is rejected.
actor ClaudeProviderRefresher {
    static let shared = ClaudeProviderRefresher()

    /// After a 429 the endpoint is known to stay limited for a while, and
    /// knocking again on the normal schedule prolongs it. Back off instead,
    /// doubling up to an hour, and reset as soon as a fetch succeeds.
    static let initialBackoff: TimeInterval = 15 * 60
    static let maximumBackoff: TimeInterval = 60 * 60

    typealias CredentialReader = @Sendable (Bool) -> ClaudeCredentialStore.Outcome
    typealias LegacyCredentialReader = @Sendable () -> ClaudeCredentialStore.Outcome
    typealias FileCredentialReader = @Sendable () -> ClaudeCredential?

    private let credentialReader: CredentialReader
    private let fileCredentialReader: FileCredentialReader
    private let fetch: @Sendable (ClaudeCredential) async throws -> QuotaSnapshot
    private let now: @Sendable () -> Date
    private var credential: ClaudeCredential?
    private var lastLookupFailure: QuotaRefreshFailure = .noCredential
    private var backoff: TimeInterval = 0
    private var blockedUntil: Date?

    init(
        home: URL = ClaudeCredentialStore.defaultCredentialDirectory,
        credentialReader: CredentialReader? = nil,
        fileCredentialReader: FileCredentialReader? = nil,
        fetch: @escaping @Sendable (ClaudeCredential) async throws -> QuotaSnapshot = { credential in
            try await ClaudeUsageClient().fetch(credential: credential)
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentialReader = credentialReader ?? { allowInteraction in
            ClaudeCredentialStore(home: home).lookup(allowInteraction: allowInteraction)
        }
        // An injected reader must not cause unrelated real credential reads.
        if let fileCredentialReader {
            self.fileCredentialReader = fileCredentialReader
        } else if credentialReader == nil {
            self.fileCredentialReader = { ClaudeCredentialStore(home: home).credentialFromFile() }
        } else {
            self.fileCredentialReader = { nil }
        }
        self.fetch = fetch
        self.now = now
    }

    init(
        home: URL = ClaudeCredentialStore.defaultCredentialDirectory,
        credentialReader: @escaping LegacyCredentialReader,
        fileCredentialReader: FileCredentialReader? = nil,
        fetch: @escaping @Sendable (ClaudeCredential) async throws -> QuotaSnapshot = { credential in
            try await ClaudeUsageClient().fetch(credential: credential)
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            home: home,
            credentialReader: { _ in credentialReader() },
            fileCredentialReader: fileCredentialReader,
            fetch: fetch,
            now: now
        )
    }

    /// `force` bypasses the backoff for an explicit manual refresh.
    /// `allowInteraction` lets that user action show Keychain authorization UI.
    func refresh(force: Bool = false, allowInteraction: Bool = false) async -> ProviderRefreshResult {
        if !force, let blockedUntil, now() < blockedUntil {
            return .failed(.rateLimited)
        }

        guard let credential = readCredentialIfNeeded(allowInteraction: allowInteraction) else {
            return .failed(lastLookupFailure)
        }
        guard !credential.hasExpired(at: now()) else {
            // Claude Code refreshes the token; sending an expired one only
            // wastes a request against a rate-limited endpoint. A cached
            // Keychain token may have been replaced by a current file token,
            // so re-read once before reporting expiry.
            self.credential = nil
            return await refreshWithFreshCredential(allowInteraction: allowInteraction)
        }

        do {
            let snapshot = try await fetch(credential)
            clearBackoff()
            return ProviderRefreshResult(snapshot: snapshot)
        } catch ClaudeUsageClientError.unauthorized {
            return await refreshWithFreshCredential(
                allowInteraction: allowInteraction,
                rejectedAccessToken: credential.accessToken
            )
        } catch ClaudeUsageClientError.rateLimited {
            recordRateLimit()
            return .failed(.rateLimited)
        } catch {
            return .failed(QuotaRefreshFailure.classify(error))
        }
    }

    private func recordRateLimit() {
        backoff = backoff == 0
            ? Self.initialBackoff
            : min(backoff * 2, Self.maximumBackoff)
        blockedUntil = now().addingTimeInterval(backoff)
    }

    private func clearBackoff() {
        backoff = 0
        blockedUntil = nil
    }

    private func refreshWithFreshCredential(
        allowInteraction: Bool,
        rejectedAccessToken: String? = nil
    ) async -> ProviderRefreshResult {
        credential = nil
        guard let refreshed = readCredentialIfNeeded(allowInteraction: allowInteraction) else {
            return .failed(lastLookupFailure)
        }
        guard refreshed.accessToken != rejectedAccessToken else {
            credential = nil
            return .failed(.unauthorized)
        }
        guard !refreshed.hasExpired(at: now()) else {
            credential = nil
            return .failed(.tokenExpired)
        }

        do {
            let snapshot = try await fetch(refreshed)
            clearBackoff()
            return ProviderRefreshResult(snapshot: snapshot)
        } catch ClaudeUsageClientError.unauthorized {
            credential = nil
            return .failed(.unauthorized)
        } catch ClaudeUsageClientError.rateLimited {
            recordRateLimit()
            return .failed(.rateLimited)
        } catch {
            return .failed(QuotaRefreshFailure.classify(error))
        }
    }

    private func readCredentialIfNeeded(allowInteraction: Bool) -> ClaudeCredential? {
        if let credential, !credential.hasExpired(at: now()), !allowInteraction {
            if let file = fileCredentialReader(), file.isUsable, !file.hasExpired(at: now()) {
                self.credential = nil
                return file
            }
            return credential
        }

        credential = nil

        switch credentialReader(allowInteraction) {
        case let .found(read, source) where read.isUsable:
            // Only Keychain credentials are cached. The credential file is
            // re-read so a token rotation is picked up without persistence.
            if source == .keychain {
                credential = read
            }
            return read
        case .found:
            lastLookupFailure = .noCredential
        case .itemNotFound:
            lastLookupFailure = .noCredential
        case let .accessDenied(status):
            lastLookupFailure = .keychainDenied(status)
        case let .unreadable(keys, byteCount, isText):
            lastLookupFailure = .unreadableCredential(
                topLevelKeys: keys,
                byteCount: byteCount,
                isText: isText
            )
        }

        return nil
    }
}
