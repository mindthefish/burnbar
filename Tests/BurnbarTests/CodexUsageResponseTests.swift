import Foundation
import Testing
@testable import Burnbar

struct CodexUsageResponseTests {
    @Test
    func mapsPrimaryAndSecondaryUsageWindowsToQuotaSnapshot() throws {
        let data = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 42,
              "limit_window_seconds": 18000,
              "reset_at": 1725000000
            },
            "secondary_window": {
              "used_percent": 73,
              "limit_window_seconds": 604800,
              "reset_at": 1725600000
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: data)

        #expect(response.quotaSnapshot == QuotaSnapshot(
            state: .available,
            windows: [
                QuotaWindow(
                    label: "5h",
                    usedPercentage: 42,
                    resetsAt: Date(timeIntervalSince1970: 1_725_000_000),
                    durationSeconds: 18_000
                ),
                QuotaWindow(
                    label: "7d",
                    usedPercentage: 73,
                    resetsAt: Date(timeIntervalSince1970: 1_725_600_000),
                    durationSeconds: 604_800
                )
            ]
        ))
    }
}