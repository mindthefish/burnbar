import Testing
@testable import Burnbar

struct ProviderQuotaSnapshotTests {
    @Test
    func unavailableSnapshotsCoverTheThreeFixedIndicators() {
        let snapshots = ProviderQuotaSnapshot.unavailableSnapshots

        #expect(snapshots.map(\.indicator) == ["C", "P", "W"])
        #expect(snapshots.map(\.displayName) == [
            "Claude Code",
            "private-openai",
            "work-openai"
        ])
        #expect(snapshots.allSatisfy { $0.snapshot == .unavailable })
    }
}