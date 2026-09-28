import Foundation
import Testing
@testable import SnaPayCore

struct FinancialMonthTests {
    @Test func startsOnFirstByDefault() {
        let month = FinancialMonth.containing(date(2026, 9, 28), startDay: 1, calendar: .israel)
        #expect(month.start == startOfDay(2026, 9, 1))
        #expect(month.end == startOfDay(2026, 10, 1))
    }

    @Test func dateBeforeStartDayBelongsToPreviousMonth() {
        let month = FinancialMonth.containing(date(2026, 9, 5), startDay: 10, calendar: .israel)
        #expect(month.start == startOfDay(2026, 8, 10))
        #expect(month.end == startOfDay(2026, 9, 10))
    }

    @Test func dateOnStartDayBelongsToNewMonth() {
        let month = FinancialMonth.containing(startOfDay(2026, 9, 10), startDay: 10, calendar: .israel)
        #expect(month.start == startOfDay(2026, 9, 10))
    }

    @Test func crossesYearBoundary() {
        let month = FinancialMonth.containing(date(2027, 1, 3), startDay: 10, calendar: .israel)
        #expect(month.start == startOfDay(2026, 12, 10))
        #expect(month.end == startOfDay(2027, 1, 10))
    }

    @Test func startDayClampsToShortMonths() {
        // Start day 31: February starts on the 28th, March back on the 31st.
        let month = FinancialMonth.containing(date(2027, 3, 1), startDay: 31, calendar: .israel)
        #expect(month.start == startOfDay(2027, 2, 28))
        #expect(month.end == startOfDay(2027, 3, 31))
    }

    @Test func previousMonth() {
        let month = FinancialMonth.containing(date(2026, 9, 15), startDay: 10, calendar: .israel)
        let previous = month.previous(startDay: 10, calendar: .israel)
        #expect(previous.start == startOfDay(2026, 8, 10))
        #expect(previous.end == month.start)
    }

    @Test func thisMonthPeriodUsesStartDay() {
        let interval = ReportingPeriod.thisMonth.interval(now: date(2026, 9, 28), monthStartDay: 10, calendar: .israel)
        #expect(interval.start == startOfDay(2026, 9, 10))
    }

    @Test func thisWeekStartsOnSundayInIsrael() {
        // 28 Sep 2026 is a Monday.
        let interval = ReportingPeriod.thisWeek.interval(now: date(2026, 9, 28), monthStartDay: 1, calendar: .israel)
        #expect(interval.start == startOfDay(2026, 9, 27))
    }
}
