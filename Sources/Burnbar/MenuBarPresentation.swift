struct MenuBarPresentation: Equatable, Sendable {
    let indicators: [MenuBarIndicator]

    init(providers: [ProviderQuotaSnapshot]) {
        indicators = providers.map(MenuBarIndicator.init)
    }
}

struct MenuBarIndicator: Equatable, Sendable {
    enum Health: Equatable, Sendable {
        case green
        case amber
        case red
    }

    enum VisualState: Equatable, Sendable {
        case available(fillFraction: Double)
        /// Keeps the last known fill so a failed refresh dims the bar instead
        /// of emptying it. Nil when nothing was ever known.
        case stale(fillFraction: Double?)
        case unavailable
    }

    let indicator: String
    let accent: ProviderQuotaSnapshot.Accent
    let visualState: VisualState
    let health: Health?
    let weeklyFillFraction: Double?

    init(provider: ProviderQuotaSnapshot) {
        indicator = provider.indicator
        accent = provider.accent
        let windows = provider.snapshot.windows
        let measured = windows.filter { $0.durationSeconds != nil }
        let longWindow = measured.count > 1
            ? measured.max { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }
            : windows.first { $0.label == "7d" }
        weeklyFillFraction = longWindow
            .map { min(1, max(0, $0.remainingPercentage / 100)) }

        switch provider.snapshot.menuBarValue {
        case let .available(usedPercentage):
            let remaining = 100 - usedPercentage
            visualState = .available(fillFraction: remaining / 100)
            switch remaining {
            case 50...:
                health = .green
            case 20...:
                health = .amber
            default:
                health = .red
            }
        case let .stale(usedPercentage):
            visualState = .stale(fillFraction: usedPercentage.map { (100 - $0) / 100 })
            health = nil
        case .unavailable:
            visualState = .unavailable
            health = nil
        }
    }
}
