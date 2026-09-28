import Foundation

/// A "financial month" that starts on a user-chosen day (e.g. the 10th, when salary lands)
/// rather than on the 1st of the calendar month.
public struct FinancialMonth: Equatable, Sendable {
    /// Inclusive start.
    public let start: Date
    /// Exclusive end (the start of the next financial month).
    public let end: Date

    public var interval: DateInterval { DateInterval(start: start, end: end) }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// The financial month containing `date`.
    ///
    /// - Parameter startDay: 1...31. When a month is shorter than `startDay`, the month
    ///   starts on its last day (a start day of 31 starts February on the 28th/29th).
    public static func containing(_ date: Date, startDay: Int, calendar: Calendar = .current) -> FinancialMonth {
        let day = min(max(startDay, 1), 31)
        let components = calendar.dateComponents([.year, .month], from: date)
        let thisMonth = calendar.date(from: components)!
        let startThisMonth = startDate(inMonthOf: thisMonth, day: day, calendar: calendar)

        let start: Date
        if date >= startThisMonth {
            start = startThisMonth
        } else {
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth)!
            start = startDate(inMonthOf: previousMonth, day: day, calendar: calendar)
        }
        let monthOfStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start))!
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthOfStart)!
        let end = startDate(inMonthOf: nextMonth, day: day, calendar: calendar)
        return FinancialMonth(start: start, end: end)
    }

    /// The financial month before this one.
    public func previous(startDay: Int, calendar: Calendar = .current) -> FinancialMonth {
        FinancialMonth.containing(start.addingTimeInterval(-1), startDay: startDay, calendar: calendar)
    }

    private static func startDate(inMonthOf month: Date, day: Int, calendar: Calendar) -> Date {
        let range = calendar.range(of: .day, in: .month, for: month)!
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = min(day, range.count)
        return calendar.date(from: components)!
    }
}

/// The period switcher on the Home screen: "השבוע" / "החודש" / "אחר".
public enum ReportingPeriod: Equatable, Sendable {
    case thisWeek
    case thisMonth
    case custom(DateInterval)

    public func interval(now: Date, monthStartDay: Int, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)!
        case .thisMonth:
            return FinancialMonth.containing(now, startDay: monthStartDay, calendar: calendar).interval
        case .custom(let interval):
            return interval
        }
    }
}
