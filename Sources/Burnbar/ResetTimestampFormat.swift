import Foundation

/// Chooses how much of a reset timestamp to show: the date is noise while the
/// window still resets today.
enum ResetTimestampFormat: Equatable, Sendable {
    case timeOnly
    case dateAndTime

    static func choose(for resetsAt: Date, now: Date, calendar: Calendar = .current) -> Self {
        calendar.isDate(resetsAt, inSameDayAs: now) ? .timeOnly : .dateAndTime
    }
}
