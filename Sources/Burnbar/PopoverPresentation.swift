import Foundation

struct PopoverPresentation: Equatable, Sendable {
    let cards: [PopoverQuotaCard]

    init(providers: [ProviderQuotaSnapshot]) {
        cards = providers.map(PopoverQuotaCard.init)
    }
}

struct PopoverQuotaCard: Equatable, Sendable {
    enum BarState: Equatable, Sendable {
        case available(fillFraction: Double, health: Health)
        case stale
        case unavailable
    }

    enum Health: Equatable, Sendable {
        case green, amber, red
    }

    let displayName: String
    let accent: ProviderQuotaSnapshot.Accent
    let state: QuotaSnapshot.State
    let windows: [QuotaWindow]
    let barState: BarState
    /// Short reason shown next to a stale or unavailable provider.
    let statusNote: String?
    let lastSuccessfulUpdate: Date?

    init(provider: ProviderQuotaSnapshot) {
        displayName = provider.displayName
        accent = provider.accent
        state = provider.snapshot.state
        windows = provider.snapshot.windows
        statusNote = provider.failure?.label
        lastSuccessfulUpdate = provider.lastSuccessfulUpdate

        switch provider.snapshot.menuBarValue {
        case let .available(usedPercentage):
            let health: Health
            let remaining = 100 - usedPercentage
            switch remaining {
            case 50...: health = .green
            case 20...: health = .amber
            default: health = .red
            }
            barState = .available(fillFraction: remaining / 100, health: health)
        case .stale:
            barState = .stale
        case .unavailable:
            barState = .unavailable
        }
    }
}
