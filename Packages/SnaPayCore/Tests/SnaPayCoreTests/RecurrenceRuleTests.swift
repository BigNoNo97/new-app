import Foundation
import Testing
@testable import SnaPayCore

struct RecurrenceRuleTests {
    @Test func monthlyOccurrencesInRange() {
        let rule = RecurrenceRule(frequency: .monthly, startDate: date(2026, 1, 15))
        let range = DateInterval(start: date(2026, 3, 1), end: date(2026, 6, 1))
        #expect(rule.occurrences(in: range, calendar: .israel) == [date(2026, 3, 15), date(2026, 4, 15), date(2026, 5, 15)])
    }

    @Test func monthEndAnchorDoesNotDrift() {
        let rule = RecurrenceRule(frequency: .monthly, startDate: date(2027, 1, 31))
        let range = DateInterval(start: date(2027, 1, 1), end: date(2027, 5, 1))
        #expect(rule.occurrences(in: range, calendar: .israel) == [
            date(2027, 1, 31), date(2027, 2, 28), date(2027, 3, 31), date(2027, 4, 30),
        ])
    }

    @Test func stopsAtEndDateInclusive() {
        let rule = RecurrenceRule(frequency: .weekly, startDate: date(2026, 9, 1), endDate: startOfDay(2026, 9, 15))
        let range = DateInterval(start: date(2026, 1, 1), end: date(2027, 1, 1))
        #expect(rule.occurrences(in: range, calendar: .israel) == [date(2026, 9, 1), date(2026, 9, 8), date(2026, 9, 15)])
    }

    @Test func yearlyAndEveryNDays() {
        let yearly = RecurrenceRule(frequency: .yearly, startDate: date(2025, 2, 10))
        #expect(yearly.nextOccurrence(after: date(2026, 3, 1), calendar: .israel) == date(2027, 2, 10))

        let everyTen = RecurrenceRule(frequency: .everyDays(10), startDate: date(2026, 9, 1))
        #expect(everyTen.nextOccurrence(after: date(2026, 9, 1), calendar: .israel) == date(2026, 9, 11))
    }

    @Test func everyTwoMonths() {
        let rule = RecurrenceRule(frequency: .everyMonths(2), startDate: date(2026, 1, 5))
        let range = DateInterval(start: date(2026, 1, 1), end: date(2026, 7, 1))
        #expect(rule.occurrences(in: range, calendar: .israel) == [date(2026, 1, 5), date(2026, 3, 5), date(2026, 5, 5)])
    }

    @Test func invalidIntervalProducesNothing() {
        let rule = RecurrenceRule(frequency: .everyDays(0), startDate: date(2026, 1, 1))
        #expect(rule.occurrences(in: DateInterval(start: date(2025, 1, 1), end: date(2027, 1, 1)), calendar: .israel).isEmpty)
    }

    @Test func noNextOccurrenceAfterEnd() {
        let rule = RecurrenceRule(frequency: .monthly, startDate: date(2026, 1, 1), endDate: date(2026, 3, 1))
        #expect(rule.nextOccurrence(after: date(2026, 3, 2), calendar: .israel) == nil)
    }
}
