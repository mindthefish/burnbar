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
    /// Remaining quota per window, ordered from shortest to longest.
    let windowFillFractions: [Double]

    init(provider: ProviderQuotaSnapshot) {
        indicator = provider.indicator
        accent = provider.accent
        let windows = provider.snapshot.windows
        windowFillFractions = windows.enumerated()
            .sorted {
                let left = Self.duration(of: $0.element)
                let right = Self.duration(of: $1.element)
                return left == right ? $0.offset < $1.offset : left < right
            }
            .map { min(1, max(0, $0.element.remainingPercentage / 100)) }

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

    private static func duration(of window: QuotaWindow) -> Int {
        if let seconds = window.durationSeconds, seconds > 0 {
            return seconds
        }
        switch window.label {
        case "5h": return 5 * 3_600
        case "7d": return 7 * 86_400
        default: return Int.max
        }
    }
}
