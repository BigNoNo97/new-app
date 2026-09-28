import Foundation

extension Calendar {
    /// Gregorian calendar pinned to Israel time, so tests don't depend on the CI machine.
    static let israel: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        calendar.firstWeekday = 1
        return calendar
    }()
}

func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, calendar: Calendar = .israel) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

func startOfDay(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar = .israel) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}
