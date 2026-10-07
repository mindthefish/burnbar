import Foundation

struct ClaudeUsageResponse: Decodable, Sendable {
    private let windows: [String: ClaudeQuotaWindow]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var windows: [String: ClaudeQuotaWindow] = [:]

        for key in container.allKeys {
            if let window = try? container.decode(ClaudeQuotaWindow.self, forKey: key) {
                windows[key.stringValue] = window
            }
        }

        self.windows = windows
    }

    var quotaSnapshot: QuotaSnapshot {
        let mapped = [
            ("5h", selectedWindow(for: "five_hour")),
            ("7d", selectedWindow(for: "seven_day"))
        ]
        .compactMap { pair -> QuotaWindow? in
            let (label, window) = pair
            guard let window, (0...100).contains(window.utilization) else {
                return nil
            }
            return QuotaWindow(
                label: label,
                usedPercentage: window.utilization,
                resetsAt: window.resetDate
            )
        }
        guard !mapped.isEmpty else {
            return .unavailable
        }
        return QuotaSnapshot(state: .available, windows: mapped)
    }

    private func selectedWindow(for baseKey: String) -> ClaudeQuotaWindow? {
        if let exact = windows[baseKey], (0...100).contains(exact.utilization) {
            return exact
        }

        // Keep utilization and reset paired. Stable key ordering resolves equal
        // utilization without depending on JSON or dictionary iteration order.
        return windows
            .filter { $0.key.hasPrefix("\(baseKey)_") && (0...100).contains($0.value.utilization) }
            .sorted {
                if $0.value.utilization == $1.value.utilization {
                    return $0.key < $1.key
                }
                return $0.value.utilization > $1.value.utilization
            }
            .first?.value
    }
}

private struct ClaudeQuotaWindow: Decodable, Sendable {
    let utilization: Double
    let resetsAt: String?

    var resetDate: Date? {
        resetsAt.flatMap(Date.parseISO8601)
    }

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension Date {
    static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
