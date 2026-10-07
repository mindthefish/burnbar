import Foundation
import Testing
@testable import Burnbar

struct PopoverPresentationTests {
    @Test
    func cardsPreserveProviderIdentityAndAvailableWindowDetails() {
        let resetDate = Date(timeIntervalSince1970: 1_725_000_000)
        let window = QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: resetDate)
        let providers = [
            ProviderQuotaSnapshot(
                indicator: "C",
                displayName: "Claude Code",
                accent: .claude,
                snapshot: QuotaSnapshot(state: .available, windows: [window])
            ),
            ProviderQuotaSnapshot(
                indicator: "P",
                displayName: "private-openai",
                accent: .privateOpenAI,
                snapshot: .unavailable
            )
        ]

        let cards = PopoverPresentation(providers: providers).cards

        #expect(cards.map(\.displayName) == ["Claude Code", "private-openai"])
        #expect(cards[0].state == .available)
        #expect(cards[0].windows == [window])
        #expect(cards[1].state == .unavailable)
        #expect(cards[1].windows.isEmpty)
    }

    @Test
    func remainingPercentageIsDerivedFromUsedPercentage() {
        let window = QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 0))
        #expect(window.remainingPercentage == 58)
    }

    @Test
    func remainingPercentageAtFullUsageIsZero() {
        let window = QuotaWindow(label: "7d", usedPercentage: 100, resetsAt: Date(timeIntervalSince1970: 0))
        #expect(window.remainingPercentage == 0)
    }

    @Test
    func remainingPercentageAtZeroUsageIs100() {
        let window = QuotaWindow(label: "5h", usedPercentage: 0, resetsAt: Date(timeIntervalSince1970: 0))
        #expect(window.remainingPercentage == 100)
    }

    @Test
    func barStateIsGreenWhenRemainingIsAtLeast50Percent() {
        let card = PopoverQuotaCard(provider: ProviderQuotaSnapshot(
            indicator: "C",
            displayName: "Claude Code",
            accent: .claude,
            snapshot: QuotaSnapshot(
                state: .available,
                windows: [QuotaWindow(label: "5h", usedPercentage: 50, resetsAt: Date(timeIntervalSince1970: 0))]
            )
        ))
        #expect(card.barState == .available(fillFraction: 0.5, health: .green))
    }

    @Test
    func barStateIsAmberWhenRemainingIsBetween20And49() {
        let card = PopoverQuotaCard(provider: ProviderQuotaSnapshot(
            indicator: "P",
            displayName: "private-openai",
            accent: .privateOpenAI,
            snapshot: QuotaSnapshot(
                state: .available,
                windows: [QuotaWindow(label: "5h", usedPercentage: 51, resetsAt: Date(timeIntervalSince1970: 0))]
            )
        ))
        #expect(card.barState == .available(fillFraction: 0.49, health: .amber))
    }

    @Test
    func barStateIsRedWhenRemainingIsBelow20() {
        let card = PopoverQuotaCard(provider: ProviderQuotaSnapshot(
            indicator: "W",
            displayName: "work-openai",
            accent: .workOpenAI,
            snapshot: QuotaSnapshot(
                state: .available,
                windows: [QuotaWindow(label: "5h", usedPercentage: 81, resetsAt: Date(timeIntervalSince1970: 0))]
            )
        ))
        #expect(card.barState == .available(fillFraction: 0.19, health: .red))
    }

    @Test
    func barStateIsStaleForStaleProvider() {
        let card = PopoverQuotaCard(provider: ProviderQuotaSnapshot(
            indicator: "P",
            displayName: "private-openai",
            accent: .privateOpenAI,
            snapshot: QuotaSnapshot(state: .stale)
        ))
        #expect(card.barState == .stale)
    }

    @Test
    func barStateIsUnavailableForUnavailableProvider() {
        let card = PopoverQuotaCard(provider: ProviderQuotaSnapshot(
            indicator: "W",
            displayName: "work-openai",
            accent: .workOpenAI,
            snapshot: .unavailable
        ))
        #expect(card.barState == .unavailable)
    }

    @Test
    func barStateFollowsTheShortWindow() {
        let card = PopoverQuotaCard(provider: ProviderQuotaSnapshot(
            indicator: "C",
            displayName: "Claude Code",
            accent: .claude,
            snapshot: QuotaSnapshot(
                state: .available,
                windows: [
                    QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 0)),
                    QuotaWindow(label: "7d", usedPercentage: 73, resetsAt: Date(timeIntervalSince1970: 0))
                ]
            )
        ))
        #expect(card.barState == .available(fillFraction: 0.58, health: .green))
    }
    @Test(arguments: [0.0, 100.0])
    func remainingBarCoversUnusedAndExhaustedQuota(usedPercentage: Double) {
        let card = PopoverQuotaCard(provider: ProviderQuotaSnapshot(
            indicator: "P", displayName: "Private", accent: .privateOpenAI,
            snapshot: QuotaSnapshot(state: .available, windows: [
                QuotaWindow(label: "5h", usedPercentage: usedPercentage, resetsAt: nil)
            ])
        ))
        #expect(card.barState == .available(
            fillFraction: (100 - usedPercentage) / 100,
            health: usedPercentage == 0 ? .green : .red
        ))
    }
}
