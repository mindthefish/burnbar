import Foundation
import Testing
@testable import Burnbar

struct MenuBarPresentationTests {
    @Test
    func indicatorsPreserveFixedOrderAndQuotaAvailability() {
        let resetDate = Date(timeIntervalSince1970: 0)
        let providers = [
            ProviderQuotaSnapshot(
                indicator: "C",
                displayName: "Claude Code",
                accent: .claude,
                snapshot: QuotaSnapshot(
                    state: .available,
                    windows: [QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: resetDate)]
                )
            ),
            ProviderQuotaSnapshot(
                indicator: "P",
                displayName: "private-openai",
                accent: .privateOpenAI,
                snapshot: QuotaSnapshot(state: .stale)
            ),
            ProviderQuotaSnapshot(
                indicator: "W",
                displayName: "work-openai",
                accent: .workOpenAI,
                snapshot: .unavailable
            )
        ]

        let indicators = MenuBarPresentation(providers: providers).indicators

        #expect(indicators.map(\.indicator) == ["C", "P", "W"])
        #expect(indicators.map(\.visualState) == [
            .available(fillFraction: 0.58),
            .stale(fillFraction: nil),
            .unavailable
        ])
    }

    @Test
    func availableIndicatorsClassifyRemainingQuotaByAcceptedThresholds() {
        let resetDate = Date(timeIntervalSince1970: 0)

        let green = MenuBarIndicator(provider: ProviderQuotaSnapshot(
            indicator: "C",
            displayName: "Claude Code",
            accent: .claude,
            snapshot: QuotaSnapshot(
                state: .available,
                windows: [QuotaWindow(label: "5h", usedPercentage: 50, resetsAt: resetDate)]
            )
        ))
        let amber = MenuBarIndicator(provider: ProviderQuotaSnapshot(
            indicator: "P",
            displayName: "private-openai",
            accent: .privateOpenAI,
            snapshot: QuotaSnapshot(
                state: .available,
                windows: [QuotaWindow(label: "5h", usedPercentage: 51, resetsAt: resetDate)]
            )
        ))
        let red = MenuBarIndicator(provider: ProviderQuotaSnapshot(
            indicator: "W",
            displayName: "work-openai",
            accent: .workOpenAI,
            snapshot: QuotaSnapshot(
                state: .available,
                windows: [QuotaWindow(label: "5h", usedPercentage: 81, resetsAt: resetDate)]
            )
        ))

        #expect(green.health == .green)
        #expect(amber.health == .amber)
        #expect(red.health == .red)
    }

    @Test
    func aStaleIndicatorKeepsTheLastKnownFill() {
        let indicator = MenuBarIndicator(provider: ProviderQuotaSnapshot(
            indicator: "C",
            displayName: "Claude Code",
            accent: .claude,
            snapshot: QuotaSnapshot(
                state: .stale,
                windows: [QuotaWindow(label: "5h", usedPercentage: 77, resetsAt: .now)]
            )
        ))

        #expect(indicator.visualState == .stale(fillFraction: 0.23))
    }
    @Test
    func windowFillsRemainIndependentAndSurviveStaleness() {
        for state in [QuotaSnapshot.State.available, .stale] {
            let indicator = MenuBarIndicator(provider: ProviderQuotaSnapshot(
                indicator: "P",
                displayName: "Private",
                accent: .privateOpenAI,
                snapshot: QuotaSnapshot(state: state, windows: [
                    QuotaWindow(label: "7d", usedPercentage: 80, resetsAt: nil),
                    QuotaWindow(label: "5h", usedPercentage: 30, resetsAt: nil)
                ])
            ))
            #expect(indicator.windowFillFractions == [0.7, 0.2])
            #expect(indicator.visualState == (state == .available
                ? .available(fillFraction: 0.7) : .stale(fillFraction: 0.7)))
        }
    }

    @Test(arguments: [0.0, 100.0])
    func remainingBarsCoverUnusedAndExhaustedQuota(usedPercentage: Double) {
        let expected = (100 - usedPercentage) / 100
        for state in [QuotaSnapshot.State.available, .stale] {
            let indicator = MenuBarIndicator(provider: ProviderQuotaSnapshot(
                indicator: "P", displayName: "Private", accent: .privateOpenAI,
                snapshot: QuotaSnapshot(state: state, windows: [
                    QuotaWindow(label: "5h", usedPercentage: usedPercentage, resetsAt: nil),
                    QuotaWindow(label: "7d", usedPercentage: usedPercentage, resetsAt: nil)
                ])
            ))
            #expect(indicator.windowFillFractions == [expected, expected])
            #expect(indicator.visualState == (state == .available
                ? .available(fillFraction: expected) : .stale(fillFraction: expected)))
        }
    }
    @Test
    func threeWindowsAreSortedByDurationAndKeepExhaustedQuota() {
        let indicator = MenuBarIndicator(provider: ProviderQuotaSnapshot(
            indicator: "W", displayName: "Work", accent: .workOpenAI,
            snapshot: QuotaSnapshot(state: .available, windows: [
                QuotaWindow(label: "7d", usedPercentage: 100, resetsAt: nil, durationSeconds: 604_800),
                QuotaWindow(label: "1d", usedPercentage: 50, resetsAt: nil, durationSeconds: 86_400),
                QuotaWindow(label: "5h", usedPercentage: 0, resetsAt: nil, durationSeconds: 18_000)
            ])
        ))
        #expect(indicator.windowFillFractions == [1, 0.5, 0])
    }

    @Test
    func windowStripsUseReportedDurationInsteadOfWeeklyLabels() {
        let indicator = MenuBarIndicator(provider: ProviderQuotaSnapshot(
            indicator: "P", displayName: "Private", accent: .privateOpenAI,
            snapshot: QuotaSnapshot(state: .available, windows: [
                QuotaWindow(label: "8d", usedPercentage: 80, resetsAt: nil, durationSeconds: 691_200),
                QuotaWindow(label: "8.75h", usedPercentage: 30, resetsAt: nil, durationSeconds: 31_500)
            ])
        ))
        #expect(indicator.visualState == .available(fillFraction: 0.7))
        #expect(indicator.windowFillFractions == [0.7, 0.2])
    }
}
