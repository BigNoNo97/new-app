import Foundation

/// A row of `public.recurring_rules`.
public struct RecurringRuleRow: Codable, Identifiable, Hashable, Sendable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case weekly
        case monthly
        case yearly
        case everyDays = "every_days"
        case everyMonths = "every_months"
    }

    public var id: UUID
    public var householdID: UUID
    public var userID: UUID
    public var categoryID: UUID?
    public var kind: EntryKind
    public var amount: Decimal
    public var currency: String
    public var merchant: String?
    public var note: String?
    public var frequency: Frequency
    public var intervalCount: Int
    /// "yyyy-MM-dd"
    public var startsOn: String
    /// "yyyy-MM-dd", inclusive
    public var endsOn: String?
    /// "yyyy-MM-dd": the last occurrence already created
    public var lastGeneratedOn: String?
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        householdID: UUID,
        userID: UUID,
        categoryID: UUID?,
        kind: EntryKind,
        amount: Decimal,
        currency: String,
        merchant: String? = nil,
        note: String? = nil,
        frequency: Frequency,
        intervalCount: Int = 1,
        startsOn: String,
        endsOn: String? = nil,
        lastGeneratedOn: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.householdID = householdID
        self.userID = userID
        self.categoryID = categoryID
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.note = note
        self.frequency = frequency
        self.intervalCount = intervalCount
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.lastGeneratedOn = lastGeneratedOn
        self.isActive = isActive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdID = try c.decode(UUID.self, forKey: .householdID)
        userID = try c.decode(UUID.self, forKey: .userID)
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        kind = try c.decode(EntryKind.self, forKey: .kind)
        amount = try c.decodeDecimal(forKey: .amount, scale: 2)
        currency = try c.decode(String.self, forKey: .currency)
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        frequency = try c.decode(Frequency.self, forKey: .frequency)
        intervalCount = try c.decode(Int.self, forKey: .intervalCount)
        startsOn = try c.decode(String.self, forKey: .startsOn)
        endsOn = try c.decodeIfPresent(String.self, forKey: .endsOn)
        lastGeneratedOn = try c.decodeIfPresent(String.self, forKey: .lastGeneratedOn)
        isActive = try c.decode(Bool.self, forKey: .isActive)
    }

    /// The schedule as a `RecurrenceRule`, or `nil` if the stored dates are malformed.
    public func schedule(calendar: Calendar = .current) -> RecurrenceRule? {
        guard let start = DayString.date(from: startsOn, calendar: calendar) else { return nil }
        let end = endsOn.flatMap { DayString.date(from: $0, calendar: calendar) }
        let n = max(intervalCount, 1)
        let recurrence: RecurrenceFrequency
        switch frequency {
        case .weekly: recurrence = n == 1 ? .weekly : .everyDays(7 * n)
        case .monthly: recurrence = n == 1 ? .monthly : .everyMonths(n)
        case .yearly: recurrence = n == 1 ? .yearly : .everyMonths(12 * n)
        case .everyDays: recurrence = .everyDays(n)
        case .everyMonths: recurrence = .everyMonths(n)
        }
        return RecurrenceRule(frequency: recurrence, startDate: start, endDate: end)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case userID = "user_id"
        case categoryID = "category_id"
        case kind, amount, currency, merchant, note, frequency
        case intervalCount = "interval_count"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case lastGeneratedOn = "last_generated_on"
        case isActive = "is_active"
    }
}

/// Creates the transactions a recurring rule owes up to today.
///
/// Each device generates only its user's rules, on launch. Occurrences get a stable external id
/// so the unique (household, source, external id) constraint makes re-runs and races harmless.
public enum RecurringPlanner {
    /// Occurrence days (start of day) after `lastGeneratedOn` and up to and including `today`.
    public static func dueDates(for rule: RecurringRuleRow, today: Date, calendar: Calendar = .current, limit: Int = 400) -> [Date] {
        guard rule.isActive, let schedule = rule.schedule(calendar: calendar) else { return [] }
        let startOfToday = calendar.startOfDay(for: today)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        var from = schedule.startDate
        if let last = rule.lastGeneratedOn.flatMap({ DayString.date(from: $0, calendar: calendar) }) {
            from = max(from, calendar.date(byAdding: .day, value: 1, to: last)!)
        }
        guard from < endOfToday else { return [] }
        return schedule.occurrences(in: DateInterval(start: from, end: endOfToday), calendar: calendar, limit: limit)
    }

    public static func externalID(ruleID: UUID, day: Date, calendar: Calendar = .current) -> String {
        "rule-\(ruleID.uuidString.lowercased())-\(DayString.string(from: day, calendar: calendar))"
    }

    /// Transactions for the due occurrences. Each is dated at noon on its day, so time-zone
    /// shifts never move it to another day.
    public static func transactions(
        for rule: RecurringRuleRow,
        today: Date,
        mainCurrency: String,
        rates: ExchangeRates?,
        cardFeePercent: Decimal,
        calendar: Calendar = .current
    ) throws -> [TransactionRow] {
        try dueDates(for: rule, today: today, calendar: calendar).map { day in
            let noon = calendar.date(byAdding: .hour, value: 12, to: day)!
            let draft = TransactionDraft(
                kind: rule.kind,
                amount: rule.amount,
                currency: rule.currency,
                categoryID: rule.categoryID,
                merchant: rule.merchant ?? "",
                note: rule.note ?? "",
                occurredAt: noon
            )
            return try draft.makeRow(
                householdID: rule.householdID,
                userID: rule.userID,
                mainCurrency: mainCurrency,
                rates: rates,
                cardFeePercent: cardFeePercent,
                source: .recurring,
                externalID: externalID(ruleID: rule.id, day: day, calendar: calendar),
                recurringRuleID: rule.id
            )
        }
    }
}
