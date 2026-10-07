import Foundation
import Testing
@testable import Burnbar

struct QuotaSnapshotTests {
    @Test
    func unavailableSnapshotHasNoWindows() {
        let snapshot = QuotaSnapshot.unavailable

        #expect(snapshot.state == .unavailable)
        #expect(snapshot.windows.isEmpty)
    }

    @Test
    func unavailableSnapshotDiscardsWindowData() {
        let window = QuotaWindow(
            label: "5h",
            usedPercentage: 42,
            resetsAt: .now
        )

        let snapshot = QuotaSnapshot(state: .unavailable, windows: [window])

        #expect(snapshot.windows.isEmpty)
    }

    @Test
    func staleSnapshotRetainsLastKnownWindows() {
        let window = QuotaWindow(
            label: "7d",
            usedPercentage: 18,
            resetsAt: Date(timeIntervalSince1970: 0)
        )

        let snapshot = QuotaSnapshot(state: .stale, windows: [window])

        #expect(snapshot.state == .stale)
        #expect(snapshot.windows == [window])
    }

    @Test
    func menuBarValuePrefersTheShortWindow() {
        let snapshot = QuotaSnapshot(
            state: .available,
            windows: [
                QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: .now),
                QuotaWindow(label: "7d", usedPercentage: 73, resetsAt: .now)
            ]
        )

        #expect(snapshot.menuBarValue == .available(usedPercentage: 42))
    }

    @Test
    func staleSnapshotKeepsItsLastKnownMenuBarValue() {
        let snapshot = QuotaSnapshot(
            state: .stale,
            windows: [QuotaWindow(label: "5h", usedPercentage: 42, resetsAt: .now)]
        )

        #expect(snapshot.menuBarValue == .stale(usedPercentage: 42))
    }

    @Test
    func staleSnapshotWithoutWindowsHasNoMenuBarValue() {
        #expect(QuotaSnapshot(state: .stale).menuBarValue == .stale(usedPercentage: nil))
    }

    @Test
    func availableSnapshotWithoutWindowsHasUnavailableMenuBarValue() {
        let snapshot = QuotaSnapshot(state: .available)

        #expect(snapshot.menuBarValue == .unavailable)
    }

    @Test
    func unavailableSnapshotHasUnavailableMenuBarValue() {
        #expect(QuotaSnapshot.unavailable.menuBarValue == .unavailable)
    }

    @Test
    func menuBarValueFallsBackToTheHighestUsedWindowWithoutAShortWindow() {
        let snapshot = QuotaSnapshot(
            state: .available,
            windows: [
                QuotaWindow(label: "7d", usedPercentage: 73, resetsAt: .now),
                QuotaWindow(label: "30d", usedPercentage: 12, resetsAt: .now)
            ]
        )

        #expect(snapshot.menuBarValue == .available(usedPercentage: 73))
    }
}
