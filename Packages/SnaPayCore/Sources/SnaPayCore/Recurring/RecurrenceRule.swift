import Foundation

/// How often a recurring charge or income repeats.
public enum RecurrenceFrequency: Codable, Equatable, Hashable, Sendable {
    case weekly
    case monthly
    case yearly
    /// Every `n` days.
    case everyDays(Int)
    /// Every `n` months.
    case everyMonths(Int)
}

/// A recurring charge or income: rent, subscriptions, salary.
public struct RecurrenceRule: Codable, Equatable, Hashable, Sendable {
    public var frequency: RecurrenceFrequency
    /// First occurrence.
    public var startDate: Date
    /// Last day an occurrence may fall on (inclusive). `nil` means it never ends.
    public var endDate: Date?

    public init(frequency: RecurrenceFrequency, startDate: Date, endDate: Date? = nil) {
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
    }

    /// All occurrences within `interval` (start inclusive, end exclusive).
    ///
    /// Monthly rules anchored on the 29th–31st fall on the last day of shorter months
    /// and return to the anchor day afterwards (Jan 31 → Feb 28 → Mar 31).
    public func occurrences(in interval: DateInterval, calendar: Calendar = .current, limit: Int = 1_000) -> [Date] {
        var result: [Date] = []
        var index = 0
        while result.count < limit {
            guard let date = occurrence(at: index, calendar: calendar) else { break }
            if let endDate, date > endOfDay(endDate, calendar: calendar) { break }
            if date >= interval.end { break }
            if date >= interval.start { result.append(date) }
            index += 1
        }
        return result
    }

    /// The next occurrence strictly after `date`, if any.
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        let horizon = DateInterval(start: date.addingTimeInterval(1), duration: 60 * 60 * 24 * 366 * 5)
        return occurrences(in: horizon, calendar: calendar, limit: 1).first
    }

    /// The `index`-th occurrence, computed from the anchor so month-end clamping never drifts.
    func occurrence(at index: Int, calendar: Calendar) -> Date? {
        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * index, to: startDate)
        case .everyDays(let n):
            guard n > 0 else { return nil }
            return calendar.date(byAdding: .day, value: n * index, to: startDate)
        case .monthly:
            return calendar.date(byAdding: .month, value: index, to: startDate)
        case .everyMonths(let n):
            guard n > 0 else { return nil }
            return calendar.date(byAdding: .month, value: n * index, to: startDate)
        case .yearly:
            return calendar.date(byAdding: .year, value: index, to: startDate)
        }
    }

    private func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay)!
    }
}
