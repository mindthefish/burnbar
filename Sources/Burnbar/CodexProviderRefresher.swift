import Foundation

/// One source's transient backoff, without storing its credential.
actor CodexProviderRefresher {
    private let read: @Sendable (URL) throws -> CodexCredential?
    private let fetch: @Sendable (CodexCredential) async throws -> QuotaSnapshot
    private let now: @Sendable () -> Date
    private var blockedUntil: Date?
    private var backoff: TimeInterval = 0

    init(
        read: @escaping @Sendable (URL) throws -> CodexCredential? = { try CodexCredentialStore(fileURL: $0).credential() },
        fetch: @escaping @Sendable (CodexCredential) async throws -> QuotaSnapshot = { try await CodexUsageClient().fetch(credential: $0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.read = read
        self.fetch = fetch
        self.now = now
    }

    func refresh(authFileURL: URL, force: Bool = false) async -> ProviderRefreshResult {
        if !force, let blockedUntil, now() < blockedUntil { return .failed(.rateLimited) }
        do {
            guard let credential = try read(authFileURL) else { return .failed(.noCredential) }
            let snapshot = try await fetch(credential)
            blockedUntil = nil
            backoff = 0
            return ProviderRefreshResult(snapshot: snapshot)
        } catch CodexUsageClientError.unauthorized {
            return .failed(.unauthorized)
        } catch let CodexUsageClientError.rateLimited(retryAfter) {
            backoff = min(backoff == 0 ? 900 : backoff * 2, 3600)
            // Honor valid server delays; bound pathological values to one day.
            let delay = min(max(backoff, retryAfter ?? 0), 86400)
            blockedUntil = now().addingTimeInterval(delay)
            return .failed(.rateLimited)
        } catch {
            return .failed(QuotaRefreshFailure.classify(error))
        }
    }
}
