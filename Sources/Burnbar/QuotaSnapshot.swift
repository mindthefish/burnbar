import Foundation

struct QuotaSnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case available
        case stale
        case unavailable
    }

    enum MenuBarValue: Equatable, Sendable {
        case available(usedPercentage: Double)
        /// Carries the last known value so the menu bar can keep showing it
        /// instead of falling back to an empty placeholder.
        case stale(usedPercentage: Double?)
        case unavailable
    }

    let state: State
    let windows: [QuotaWindow]

    init(state: State, windows: [QuotaWindow] = []) {
        self.state = state
        self.windows = state == .unavailable ? [] : windows
    }

    static let unavailable = QuotaSnapshot(state: .unavailable, windows: [])

    var menuBarValue: MenuBarValue {
        switch state {
        case .available:
            guard let leadingUsedPercentage else {
                return .unavailable
            }

            return .available(usedPercentage: leadingUsedPercentage)
        case .stale:
            return .stale(usedPercentage: leadingUsedPercentage)
        case .unavailable:
            return .unavailable
        }
    }

    /// The short window moves fastest and is the one worth watching, so it wins
    /// over a merely higher long-window utilisation.
    private var leadingUsedPercentage: Double? {
        let shortest = windows.filter { ($0.durationSeconds ?? 0) > 0 }
            .min { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }
        let leading = shortest
            ?? windows.first { $0.label == QuotaWindow.shortWindowLabel }
            ?? windows.max { $0.usedPercentage < $1.usedPercentage }
        return leading?.usedPercentage
    }
}

extension QuotaSnapshot {
    /// Applies a refresh result. A refresh that produced no data keeps the last
    /// known windows and marks them `stale` instead of dropping them, so a single
    /// failed request does not blank out the display.
    func superseded(by refreshed: QuotaSnapshot) -> QuotaSnapshot {
        guard refreshed.state == .unavailable, !windows.isEmpty else {
            return refreshed
        }

        return QuotaSnapshot(state: .stale, windows: windows)
    }
}

struct QuotaWindow: Equatable, Sendable {
    static let shortWindowLabel = "5h"

    let label: String
    let usedPercentage: Double
    /// Absent when the provider reports usage for a window without an active
    /// reset time. Never invent one.
    let resetsAt: Date?
    /// Absent when the provider does not report the window's duration.
    let durationSeconds: Int?

    init(label: String, usedPercentage: Double, resetsAt: Date?, durationSeconds: Int? = nil) {
        self.label = label
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
        self.durationSeconds = durationSeconds
    }

    var remainingPercentage: Double { 100 - usedPercentage }
}
