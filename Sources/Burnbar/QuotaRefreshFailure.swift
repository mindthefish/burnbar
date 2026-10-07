import Foundation
import Security

/// Why a refresh produced no data. Shown in the popover so a missing value is
/// explainable rather than silent.
enum QuotaRefreshFailure: Equatable, Sendable {
    case noCredential
    case keychainDenied(OSStatus)
    /// The item was readable but held no token we recognise. Carries the
    /// top-level keys, which are field names, never secrets.
    case unreadableCredential(topLevelKeys: [String], byteCount: Int, isText: Bool)
    case rateLimited
    case unauthorized
    case tokenExpired
    case offline
    case unexpectedResponse

    var label: String {
        switch self {
        case .noCredential: "No credential"
        case .keychainDenied: "Credential access required"
        case let .unreadableCredential(keys, byteCount, isText):
            keys.isEmpty
                ? "Credential unreadable (\(byteCount) B, \(isText ? "text" : "binary"))"
                : "Credential unreadable (\(keys.joined(separator: ", ")))"
        case .rateLimited: "Rate limited"
        case .unauthorized: "Token rejected"
        case .tokenExpired: "Token expired"
        case .offline: "Offline"
        case .unexpectedResponse: "Unexpected response"
        }
    }

    /// Classifies a transport error; URLError covers the offline and timeout cases.
    static func classify(_ error: Error) -> QuotaRefreshFailure {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .timedOut:
                return .offline
            default:
                return .unexpectedResponse
            }
        }
        return .unexpectedResponse
    }
}

/// A refresh result plus the reason it carries no data, if any.
struct ProviderRefreshResult: Equatable, Sendable {
    let snapshot: QuotaSnapshot
    let failure: QuotaRefreshFailure?

    init(snapshot: QuotaSnapshot, failure: QuotaRefreshFailure? = nil) {
        self.snapshot = snapshot
        self.failure = failure
    }

    static func failed(_ failure: QuotaRefreshFailure) -> ProviderRefreshResult {
        ProviderRefreshResult(snapshot: .unavailable, failure: failure)
    }
}
