import Foundation

public struct PeriodTotals: Equatable, Sendable {
    public var expenses: Decimal
    public var income: Decimal
    public var count: Int

    public var balance: Decimal { income - expenses }

    public static let zero = PeriodTotals(expenses: 0, income: 0, count: 0)
}

public struct CategoryTotal: Equatable, Sendable {
    public var categoryID: UUID?
    public var total: Decimal
    /// Share of the kind's total, 0...1.
    public var share: Double
}

public struct DayGroup: Identifiable, Equatable, Sendable {
    public var day: Date
    public var transactions: [TransactionRow]
    public var id: Date { day }

    /// Net for the day in the main currency (income minus expenses).
    public var net: Decimal { transactions.reduce(0) { $0 + $1.signedAmount } }
}

public enum TransactionSummary {
    public static func totals(_ transactions: [TransactionRow], in interval: DateInterval? = nil) -> PeriodTotals {
        var result = PeriodTotals.zero
        for transaction in transactions where interval.map({ contains($0, transaction.occurredAt) }) ?? true {
            switch transaction.kind {
            case .expense: result.expenses += transaction.amount
            case .income: result.income += transaction.amount
            }
            result.count += 1
        }
        return result
    }

    /// Totals per category for one kind, largest first. Uncategorized entries are grouped under `nil`.
    public static func byCategory(_ transactions: [TransactionRow], kind: EntryKind = .expense) -> [CategoryTotal] {
        var sums: [UUID?: Decimal] = [:]
        for transaction in transactions where transaction.kind == kind {
            sums[transaction.categoryID, default: 0] += transaction.amount
        }
        let total = sums.values.reduce(0, +)
        return sums
            .map { id, sum in
                CategoryTotal(
                    categoryID: id,
                    total: sum,
                    share: total == 0 ? 0 : NSDecimalNumber(decimal: sum / total).doubleValue
                )
            }
            .sorted { $0.total != $1.total ? $0.total > $1.total : ($0.categoryID?.uuidString ?? "") < ($1.categoryID?.uuidString ?? "") }
    }

    /// Newest day first; newest transaction first within a day.
    public static func groupedByDay(_ transactions: [TransactionRow], calendar: Calendar = .current) -> [DayGroup] {
        let groups = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.occurredAt) }
        return groups
            .map { day, items in DayGroup(day: day, transactions: sortedNewestFirst(items)) }
            .sorted { $0.day > $1.day }
    }

    public static func sortedNewestFirst(_ transactions: [TransactionRow]) -> [TransactionRow] {
        transactions.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    /// The interval of the same length right before `interval`, for "vs. last period".
    public static func previousInterval(of interval: DateInterval, period: ReportingPeriod, monthStartDay: Int, calendar: Calendar = .current) -> DateInterval {
        switch period {
        case .thisMonth:
            return FinancialMonth.containing(interval.start, startDay: monthStartDay, calendar: calendar)
                .previous(startDay: monthStartDay, calendar: calendar).interval
        case .thisWeek:
            let start = calendar.date(byAdding: .day, value: -7, to: interval.start)!
            return DateInterval(start: start, end: interval.start)
        case .custom:
            return DateInterval(start: interval.start.addingTimeInterval(-interval.duration), end: interval.start)
        }
    }

    /// Half-open containment (start inclusive, end exclusive), unlike `DateInterval.contains`.
    static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }
}
