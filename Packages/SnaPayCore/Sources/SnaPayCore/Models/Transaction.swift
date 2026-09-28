import Foundation

/// Where a transaction came from (`public.transaction_source`).
public enum TransactionSource: String, Codable, Sendable, CaseIterable {
    case manual
    case applePay = "apple_pay"
    case imported = "import"
    case receipt
    case recurring
    case openBanking = "open_banking"
}

/// A row of `public.transactions`.
///
/// `originalAmount`/`originalCurrency` are what was paid; `amount`/`currency` are the cost in the
/// user's main currency, card fee included. Totals always use `amount`.
public struct TransactionRow: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var householdID: UUID
    public var userID: UUID
    public var categoryID: UUID?
    public var kind: EntryKind
    public var originalAmount: Decimal
    public var originalCurrency: String
    public var exchangeRate: Decimal
    public var feeAmount: Decimal
    public var amount: Decimal
    public var currency: String
    public var merchant: String?
    public var note: String?
    public var occurredAt: Date
    public var source: TransactionSource
    public var externalID: String?
    public var recurringRuleID: UUID?
    public var receiptPath: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: UUID = UUID(),
        householdID: UUID,
        userID: UUID,
        categoryID: UUID?,
        kind: EntryKind,
        originalAmount: Decimal,
        originalCurrency: String,
        exchangeRate: Decimal = 1,
        feeAmount: Decimal = 0,
        amount: Decimal,
        currency: String,
        merchant: String? = nil,
        note: String? = nil,
        occurredAt: Date,
        source: TransactionSource = .manual,
        externalID: String? = nil,
        recurringRuleID: UUID? = nil,
        receiptPath: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.householdID = householdID
        self.userID = userID
        self.categoryID = categoryID
        self.kind = kind
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.exchangeRate = exchangeRate
        self.feeAmount = feeAmount
        self.amount = amount
        self.currency = currency
        self.merchant = merchant
        self.note = note
        self.occurredAt = occurredAt
        self.source = source
        self.externalID = externalID
        self.recurringRuleID = recurringRuleID
        self.receiptPath = receiptPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdID = try c.decode(UUID.self, forKey: .householdID)
        userID = try c.decode(UUID.self, forKey: .userID)
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        kind = try c.decode(EntryKind.self, forKey: .kind)
        originalAmount = try c.decodeDecimal(forKey: .originalAmount, scale: 2)
        originalCurrency = try c.decode(String.self, forKey: .originalCurrency)
        exchangeRate = try c.decodeDecimal(forKey: .exchangeRate, scale: 8)
        feeAmount = try c.decodeDecimal(forKey: .feeAmount, scale: 2)
        amount = try c.decodeDecimal(forKey: .amount, scale: 2)
        currency = try c.decode(String.self, forKey: .currency)
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        occurredAt = try c.decode(Date.self, forKey: .occurredAt)
        source = try c.decode(TransactionSource.self, forKey: .source)
        externalID = try c.decodeIfPresent(String.self, forKey: .externalID)
        recurringRuleID = try c.decodeIfPresent(UUID.self, forKey: .recurringRuleID)
        receiptPath = try c.decodeIfPresent(String.self, forKey: .receiptPath)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// Whether the amount was paid in a currency other than the main one.
    public var isForeign: Bool { originalCurrency != currency }

    /// Signed amount in the main currency: expenses negative, income positive.
    public var signedAmount: Decimal { kind == .expense ? -amount : amount }

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case userID = "user_id"
        case categoryID = "category_id"
        case kind
        case originalAmount = "original_amount"
        case originalCurrency = "original_currency"
        case exchangeRate = "exchange_rate"
        case feeAmount = "fee_amount"
        case amount, currency, merchant, note
        case occurredAt = "occurred_at"
        case source
        case externalID = "external_id"
        case recurringRuleID = "recurring_rule_id"
        case receiptPath = "receipt_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A row of `public.categories`, as read back from the server.
public struct Category: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var householdID: UUID
    public var name: String
    public var emoji: String
    public var color: String
    public var kind: EntryKind
    public var sortOrder: Int
    public var isArchived: Bool
    /// Travel categories: expenses default to this currency between the trip dates.
    public var tripCurrency: String?
    /// "yyyy-MM-dd"
    public var tripStartsOn: String?
    /// "yyyy-MM-dd"
    public var tripEndsOn: String?

    public init(
        id: UUID = UUID(),
        householdID: UUID,
        name: String,
        emoji: String,
        color: String,
        kind: EntryKind = .expense,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        tripCurrency: String? = nil,
        tripStartsOn: String? = nil,
        tripEndsOn: String? = nil
    ) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.emoji = emoji
        self.color = color
        self.kind = kind
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.tripCurrency = tripCurrency
        self.tripStartsOn = tripStartsOn
        self.tripEndsOn = tripEndsOn
    }

    public var isTrip: Bool { tripCurrency != nil }

    /// Whether this is a trip that covers `date` (inclusive of both end days).
    public func isActiveTrip(on date: Date, calendar: Calendar = .current) -> Bool {
        guard isTrip, !isArchived,
              let start = tripStartsOn.flatMap({ DayString.date(from: $0, calendar: calendar) }) else { return false }
        let day = calendar.startOfDay(for: date)
        if day < start { return false }
        if let end = tripEndsOn.flatMap({ DayString.date(from: $0, calendar: calendar) }), day > end { return false }
        return true
    }

    public var draft: CategoryDraft {
        CategoryDraft(id: id, name: name, emoji: emoji, colorHex: color, kind: kind)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case name, emoji, color, kind
        case sortOrder = "sort_order"
        case isArchived = "is_archived"
        case tripCurrency = "trip_currency"
        case tripStartsOn = "trip_starts_on"
        case tripEndsOn = "trip_ends_on"
    }
}

/// A member of the user's household, for "who logged this" and the member filter.
public struct HouseholdMember: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var fullName: String

    public init(id: UUID, fullName: String) {
        self.id = id
        self.fullName = fullName
    }

    public var firstName: String { PersonName.firstName(from: fullName) }

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
    }
}

/// Date-only columns ("yyyy-MM-dd") ↔ Date at the start of that day.
public enum DayString {
    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(from string: String, calendar: Calendar = .current) -> Date? {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == parts[2] else { return nil }
        return date
    }
}
