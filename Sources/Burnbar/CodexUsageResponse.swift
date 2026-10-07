import Foundation

struct CodexUsageResponse: Decodable, Sendable {
    private let rateLimit: RateLimit?

    var quotaSnapshot: QuotaSnapshot {
        let windows = [
            rateLimit?.primaryWindow,
            rateLimit?.secondaryWindow
        ]
        .compactMap { $0 }
        .compactMap(QuotaWindow.init)

        guard !windows.isEmpty else {
            return .unavailable
        }

        return QuotaSnapshot(state: .available, windows: windows)
    }

    private enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }
}

private struct RateLimit: Decodable, Sendable {
    let primaryWindow: CodexUsageWindow?
    let secondaryWindow: CodexUsageWindow?

    private enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexUsageWindow: Decodable, Sendable {
    let usedPercentage: Double
    let limitWindowSeconds: Int
    let resetAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
}

private extension QuotaWindow {
    init?(_ codexWindow: CodexUsageWindow) {
        guard codexWindow.limitWindowSeconds > 0,
              (0...100).contains(codexWindow.usedPercentage) else {
            return nil
        }

        self.init(
            label: Self.durationLabel(seconds: codexWindow.limitWindowSeconds),
            usedPercentage: codexWindow.usedPercentage,
            resetsAt: Date(timeIntervalSince1970: codexWindow.resetAt),
            durationSeconds: codexWindow.limitWindowSeconds
        )
    }

    static func durationLabel(seconds: Int) -> String {
        let unit: (seconds: Int, suffix: String)
        if seconds.isMultiple(of: 86_400) {
            unit = (86_400, "d")
        } else if seconds >= 3_600 {
            unit = (3_600, "h")
        } else if seconds >= 60 {
            unit = (60, "m")
        } else {
            unit = (1, "s")
        }

        var value = String(
            format: "%.2f", locale: Locale(identifier: "en_US_POSIX"),
            Double(seconds) / Double(unit.seconds)
        )
        while value.hasSuffix("0") {
            value.removeLast()
        }
        if value.hasSuffix(".") {
            value.removeLast()
        }
        return value + unit.suffix
    }
}
