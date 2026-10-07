import Foundation

struct ProviderQuotaSnapshot: Equatable, Sendable {
    enum Accent: Equatable, Sendable {
        case claude
        case privateOpenAI
        case workOpenAI
        case custom(hex: String)
    }

    let indicator: String
    let displayName: String
    let accent: Accent
    let snapshot: QuotaSnapshot
    /// Why the last refresh produced no data, if it failed.
    let failure: QuotaRefreshFailure?
    /// Completion time of the last successful quota response, retained on failure.
    let lastSuccessfulUpdate: Date?

    init(
        indicator: String,
        displayName: String,
        accent: Accent,
        snapshot: QuotaSnapshot,
        failure: QuotaRefreshFailure? = nil,
        lastSuccessfulUpdate: Date? = nil
    ) {
        self.indicator = indicator
        self.displayName = displayName
        self.accent = accent
        self.snapshot = snapshot
        self.failure = failure
        self.lastSuccessfulUpdate = lastSuccessfulUpdate
    }

    static let unavailableSnapshots = [
        ProviderQuotaSnapshot(
            indicator: "C",
            displayName: "Claude Code",
            accent: .claude,
            snapshot: .unavailable
        ),
        ProviderQuotaSnapshot(
            indicator: "P",
            displayName: "private-openai",
            accent: .privateOpenAI,
            snapshot: .unavailable
        ),
        ProviderQuotaSnapshot(
            indicator: "W",
            displayName: "work-openai",
            accent: .workOpenAI,
            snapshot: .unavailable
        )
    ]
}
