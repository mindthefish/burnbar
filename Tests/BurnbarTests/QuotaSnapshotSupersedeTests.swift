import Foundation
import Testing
@testable import Burnbar

struct QuotaSnapshotSupersedeTests {
    private let window = QuotaWindow(
        label: "5h",
        usedPercentage: 42,
        resetsAt: Date(timeIntervalSince1970: 0)
    )

    @Test
    func aSuccessfulRefreshReplacesThePreviousSnapshot() {
        let previous = QuotaSnapshot(state: .available, windows: [window])
        let refreshed = QuotaSnapshot(
            state: .available,
            windows: [QuotaWindow(label: "5h", usedPercentage: 61, resetsAt: window.resetsAt)]
        )

        #expect(previous.superseded(by: refreshed) == refreshed)
    }

    @Test
    func aFailedRefreshKeepsTheLastKnownWindowsAsStale() {
        let previous = QuotaSnapshot(state: .available, windows: [window])

        let result = previous.superseded(by: .unavailable)

        #expect(result.state == .stale)
        #expect(result.windows == [window])
    }

    @Test
    func staleWindowsSurviveRepeatedFailures() {
        let stale = QuotaSnapshot(state: .stale, windows: [window])

        let result = stale.superseded(by: .unavailable)

        #expect(result.state == .stale)
        #expect(result.windows == [window])
    }

    @Test
    func aFailedRefreshStaysUnavailableWithoutPreviousWindows() {
        #expect(QuotaSnapshot.unavailable.superseded(by: .unavailable) == .unavailable)
    }
}
