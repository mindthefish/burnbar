import Foundation
import Testing
@testable import Burnbar

struct DynamicQuotaWindowTests {
    @Test(arguments: [
        (18_000, "5h"), (604_800, "7d"), (31_500, "8.75h"),
        (7_200, "2h"), (5_400, "1.5h"), (90, "1.5m"), (15, "15s")
    ])
    func decodesReportedDuration(seconds: Int, label: String) throws {
        let snapshot = try decodeWindow(seconds: seconds)

        #expect(snapshot.state == .available)
        #expect(snapshot.windows.first?.label == label)
        #expect(snapshot.windows.first?.durationSeconds == seconds)
    }

    @Test(arguments: [0, -1, -18_000])
    func rejectsNonpositiveDuration(seconds: Int) throws {
        #expect(try decodeWindow(seconds: seconds) == .unavailable)
    }

    @Test(arguments: [QuotaSnapshot.State.available, .stale])
    func prefersShortestReportedWindow(state: QuotaSnapshot.State) {
        let snapshot = QuotaSnapshot(state: state, windows: [
            QuotaWindow(label: "5h", usedPercentage: 95, resetsAt: nil),
            QuotaWindow(label: "7d", usedPercentage: 80, resetsAt: nil, durationSeconds: 604_800),
            QuotaWindow(label: "8.75h", usedPercentage: 42, resetsAt: nil, durationSeconds: 31_500)
        ])

        let expected: QuotaSnapshot.MenuBarValue = state == .available
            ? .available(usedPercentage: 42) : .stale(usedPercentage: 42)
        #expect(snapshot.menuBarValue == expected)
    }

    @Test
    func keepsDistinctWindowsEvenWhenTheirDisplayLabelsMatch() throws {
        let data = Data("""
        {"rate_limit":{
          "primary_window":{"used_percent":10,"limit_window_seconds":3600,"reset_at":1725000000},
          "secondary_window":{"used_percent":90,"limit_window_seconds":3601,"reset_at":1725000001}
        }}
        """.utf8)
        let snapshot = try JSONDecoder().decode(CodexUsageResponse.self, from: data).quotaSnapshot
        #expect(snapshot.windows.map(\.label) == ["1h", "1h"])
        #expect(snapshot.windows.map(\.durationSeconds) == [3600, 3601])
        #expect(snapshot.windows.map(\.usedPercentage) == [10, 90])
        #expect(snapshot.menuBarValue == .available(usedPercentage: 10))
    }

    private func decodeWindow(seconds: Int) throws -> QuotaSnapshot {
        let data = Data("""
        {"rate_limit":{"primary_window":{
            "used_percent":42,"limit_window_seconds":\(seconds),"reset_at":1725000000
        }}}
        """.utf8)
        return try JSONDecoder().decode(CodexUsageResponse.self, from: data).quotaSnapshot
    }
}
