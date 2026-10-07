import Foundation
import Testing
@testable import Burnbar

struct ResetTimestampFormatTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")!
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    @Test
    func showsOnlyTheTimeForAResetLaterToday() {
        let format = ResetTimestampFormat.choose(
            for: date("2026-08-23T15:30:00+02:00"),
            now: date("2026-08-23T11:05:00+02:00"),
            calendar: calendar
        )

        #expect(format == .timeOnly)
    }

    @Test
    func showsTheDateForAResetOnAnotherDay() {
        let format = ResetTimestampFormat.choose(
            for: date("2026-08-26T13:00:00+02:00"),
            now: date("2026-08-23T11:05:00+02:00"),
            calendar: calendar
        )

        #expect(format == .dateAndTime)
    }

    @Test
    func treatsJustAfterMidnightAsAnotherDay() {
        let format = ResetTimestampFormat.choose(
            for: date("2026-08-24T00:30:00+02:00"),
            now: date("2026-08-23T23:50:00+02:00"),
            calendar: calendar
        )

        #expect(format == .dateAndTime)
    }
}
