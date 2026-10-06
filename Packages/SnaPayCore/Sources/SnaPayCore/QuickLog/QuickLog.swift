import Foundation

/// A payment handed over by the Shortcuts "Transaction" automation right after Apple Pay.
///
/// It waits in the quick-log inbox (shared App Group file) until the user picks a category
/// and the app turns it into a transaction.
public struct CapturedPayment: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var amount: Decimal
    public var currency: String
    public var merchant: String
    public var card: String?
    public var capturedAt: Date
    /// Set once the user picked a category.
    public var categoryID: UUID?
    /// The user's note ("ארוחה עם דנה"), from the quick-log card or Home.
    public var note: String?
    /// The on-device model's guess, kept when neither the household's history nor
    /// `MerchantCatalog` knew the merchant (see `QuickLogContext.likelyCategory`).
    public var suggestedCategoryID: UUID?
    /// Stable id for server-side de-duplication (`transactions.external_id`).
    public var externalID: String

    public init(
        id: UUID = UUID(),
        amount: Decimal,
        currency: String,
        merchant: String,
        card: String? = nil,
        capturedAt: Date = .now,
        categoryID: UUID? = nil,
        note: String? = nil,
        suggestedCategoryID: UUID? = nil,
        calendar: Calendar = .current
    ) {
        let cleanAmount = amount.rounded(scale: 2)
        let cleanCurrency = currency.uppercased()
        let cleanMerchant = String(merchant.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let trimmedCard = card?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCard = trimmedCard?.isEmpty == false ? trimmedCard : nil
        self.id = id
        self.amount = cleanAmount
        self.currency = cleanCurrency
        self.merchant = cleanMerchant
        self.card = cleanCard
        self.capturedAt = capturedAt
        self.categoryID = categoryID
        self.note = Self.cleanNote(note)
        self.suggestedCategoryID = suggestedCategoryID
        self.externalID = Self.makeExternalID(
            amount: cleanAmount, currency: cleanCurrency, merchant: cleanMerchant,
            card: cleanCard, capturedAt: capturedAt, calendar: calendar
        )
    }

    public var isCategorized: Bool { categoryID != nil }

    /// The draft the app saves once a category is chosen.
    public var draft: TransactionDraft {
        TransactionDraft(kind: .expense, amount: amount, currency: currency, categoryID: categoryID,
                         merchant: merchant, note: note ?? "", occurredAt: capturedAt)
    }

    /// Trimmed, at most 500 characters, and `nil` when empty.
    public static func cleanNote(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(500))
    }

    /// Whether `other` is most likely the same payment reported twice (the automation can fire
    /// more than once for one tap).
    public func isDuplicate(of other: CapturedPayment, window: TimeInterval = 120) -> Bool {
        amount == other.amount
            && currency == other.currency
            && CategorySuggester.normalize(merchant) == CategorySuggester.normalize(other.merchant)
            && card == other.card
            && abs(capturedAt.timeIntervalSince(other.capturedAt)) < window
    }

    /// "applepay-" + a hash of the card, merchant, amount and minute of the payment.
    ///
    /// Uses FNV-1a rather than `Hasher`, whose seed changes on every launch.
    public static func makeExternalID(
        amount: Decimal, currency: String, merchant: String, card: String?,
        capturedAt: Date, calendar: Calendar = .current
    ) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: capturedAt)
        let minute = String(format: "%04d%02d%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        let key = [
            card?.lowercased() ?? "",
            CategorySuggester.normalize(merchant),
            NSDecimalNumber(decimal: amount.rounded(scale: 2)).stringValue,
            currency.uppercased(),
            minute,
        ].joined(separator: "|")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "applepay-" + String(hash, radix: 16)
    }
}

/// Payments captured by the automation that the app hasn't turned into transactions yet.
public struct QuickLogInbox: Codable, Equatable, Sendable {
    /// Oldest first.
    public private(set) var payments: [CapturedPayment]
    /// When the first payment ever arrived: the setup guide's "it works" moment.
    public private(set) var firstCaptureAt: Date?

    public static let capacity = 200

    public init(payments: [CapturedPayment] = [], firstCaptureAt: Date? = nil) {
        self.payments = payments
        self.firstCaptureAt = firstCaptureAt
    }

    /// Adds a payment unless it duplicates one already waiting. Returns the payment kept in the
    /// inbox (the existing one for a duplicate).
    @discardableResult
    public mutating func add(_ payment: CapturedPayment) -> CapturedPayment {
        if firstCaptureAt == nil { firstCaptureAt = payment.capturedAt }
        if let existing = payments.first(where: { $0.externalID == payment.externalID || $0.isDuplicate(of: payment) }) {
            return existing
        }
        payments.append(payment)
        if payments.count > Self.capacity {
            payments.removeFirst(payments.count - Self.capacity)
        }
        return payment
    }

    public mutating func categorize(_ id: UUID, as categoryID: UUID) {
        guard let index = payments.firstIndex(where: { $0.id == id }) else { return }
        payments[index].categoryID = categoryID
    }

    public mutating func setNote(_ id: UUID, to note: String?) {
        guard let index = payments.firstIndex(where: { $0.id == id }) else { return }
        payments[index].note = CapturedPayment.cleanNote(note)
    }

    public mutating func setSuggestion(_ id: UUID, to categoryID: UUID?) {
        guard let index = payments.firstIndex(where: { $0.id == id }) else { return }
        payments[index].suggestedCategoryID = categoryID
    }

    /// Undo on the quick-log card: the payment waits for a category again.
    public mutating func clearCategory(_ id: UUID) {
        guard let index = payments.firstIndex(where: { $0.id == id }) else { return }
        payments[index].categoryID = nil
    }

    public mutating func remove(_ ids: Set<UUID>) {
        payments.removeAll { ids.contains($0.id) }
    }

    public func payment(_ id: UUID) -> CapturedPayment? {
        payments.first { $0.id == id }
    }

    /// Waiting for the user to pick a category, newest first.
    public var uncategorized: [CapturedPayment] {
        payments.filter { !$0.isCategorized }.reversed()
    }

    /// Categorized and ready to become transactions.
    public var categorized: [CapturedPayment] {
        payments.filter(\.isCategorized)
    }
}

/// What the quick-log intent needs to work without opening the app: who is signed in, their
/// categories, rates and suggestion history. The app rewrites it (App Group file) on every sync.
public struct QuickLogContext: Codable, Equatable, Sendable {
    public var userID: UUID
    public var householdID: UUID
    public var mainCurrency: String
    public var cardFeePercent: Decimal
    public var isEnabled: Bool
    /// Expense categories in the user's order, archived ones excluded.
    public var categories: [CategoryItem]
    public var rates: ExchangeRates?
    public var suggester: CategorySuggester
    /// Remind about a payment still waiting for a category (notification setting).
    public var remindsPendingCapture: Bool

    public init(
        userID: UUID,
        householdID: UUID,
        mainCurrency: String,
        cardFeePercent: Decimal,
        isEnabled: Bool,
        categories: [CategoryItem],
        rates: ExchangeRates?,
        suggester: CategorySuggester,
        remindsPendingCapture: Bool = true
    ) {
        self.userID = userID
        self.householdID = householdID
        self.mainCurrency = mainCurrency
        self.cardFeePercent = cardFeePercent
        self.isEnabled = isEnabled
        self.categories = categories.filter { $0.kind == .expense && !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
        self.rates = rates
        self.suggester = suggester
        self.remindsPendingCapture = remindsPendingCapture
    }

    enum CodingKeys: String, CodingKey {
        case userID, householdID, mainCurrency, cardFeePercent, isEnabled, categories, rates, suggester
        case remindsPendingCapture
    }

    /// Files written by an older version lack newer keys; those get their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(UUID.self, forKey: .userID)
        householdID = try c.decode(UUID.self, forKey: .householdID)
        mainCurrency = try c.decode(String.self, forKey: .mainCurrency)
        cardFeePercent = try c.decode(Decimal.self, forKey: .cardFeePercent)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        categories = try c.decode([CategoryItem].self, forKey: .categories)
        rates = try c.decodeIfPresent(ExchangeRates.self, forKey: .rates)
        suggester = try c.decode(CategorySuggester.self, forKey: .suggester)
        remindsPendingCapture = try c.decodeIfPresent(Bool.self, forKey: .remindsPendingCapture) ?? true
    }

    /// The category to pick for the user, or `nil` when there's no good reason to pick one:
    /// a trip running in the payment's currency, then what the household chose for this
    /// merchant before, then `MerchantCatalog`, then the on-device model's guess.
    public func likelyCategory(for payment: CapturedPayment, calendar: Calendar = .current) -> CategoryItem? {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let trip = categories.first(where: {
            $0.isTrip && $0.tripCurrency == payment.currency && $0.isActiveTrip(on: payment.capturedAt, calendar: calendar)
        }) {
            return trip
        }
        let everyday = categories.filter { !$0.isTrip }
        if suggester.knows(merchant: payment.merchant, among: everyday.map(\.id.uuidString)),
           let top = suggester.suggest(for: payment.merchant, available: everyday.map(\.id.uuidString), count: 1).first,
           let category = UUID(uuidString: top).flatMap({ byID[$0] }) {
            return category
        }
        if let known = MerchantCatalog.category(forMerchant: payment.merchant, in: everyday) {
            return known
        }
        return payment.suggestedCategoryID.flatMap { byID[$0] }.flatMap { $0.isTrip ? nil : $0 }
    }

    /// Categories to offer for `payment`, most likely first: `likelyCategory`, then the
    /// household's usage. A trip running on the payment's date in the payment's currency always
    /// comes first.
    public func suggestions(for payment: CapturedPayment, count: Int = 6, calendar: Calendar = .current) -> [CategoryItem] {
        let byID = Dictionary(categories.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let active = categories.filter { $0.isTrip && $0.isActiveTrip(on: payment.capturedAt, calendar: calendar) }
        // Trips that aren't running are hidden; the running ones are offered only if they match.
        let everyday = categories.filter { !$0.isTrip }
        let tripFirst = active.filter { $0.tripCurrency == payment.currency }
        let otherTrips = active.filter { $0.tripCurrency != payment.currency }
        let ranked = suggester.suggest(
            for: payment.merchant,
            available: (everyday + otherTrips).map(\.id.uuidString),
            count: max(count - tripFirst.count, 0)
        ).compactMap { byID[$0] }
        var ordered = tripFirst + ranked
        if tripFirst.isEmpty, let likely = likelyCategory(for: payment, calendar: calendar) {
            ordered.removeAll { $0.id == likely.id }
            ordered.insert(likely, at: 0)
        }
        return Array(ordered.prefix(count))
    }

    /// The transaction for a categorized payment. Throws `CurrencyConverterError.missingRate`
    /// when a foreign payment has no rate yet.
    public func makeRow(for payment: CapturedPayment) throws -> TransactionRow {
        var row = try payment.draft.makeRow(
            id: payment.id,
            householdID: householdID,
            userID: userID,
            mainCurrency: mainCurrency,
            rates: rates,
            cardFeePercent: cardFeePercent,
            source: .applePay,
            externalID: payment.externalID
        )
        row.createdAt = payment.capturedAt
        return row
    }

    /// The cost in the main currency for the card's second line, or `nil` when paying in the
    /// main currency (or without a rate).
    public func conversion(for payment: CapturedPayment) -> Conversion? {
        payment.draft.conversion(mainCurrency: mainCurrency, rates: rates, cardFeePercent: cardFeePercent)
    }
}

/// An entry of `merchant_map` in Firestore: how often the household filed a merchant under a
/// category.
public struct MerchantCategoryRow: Codable, Hashable, Sendable {
    public var householdID: UUID
    public var merchantKey: String
    public var categoryID: UUID
    public var timesUsed: Int

    public init(householdID: UUID, merchantKey: String, categoryID: UUID, timesUsed: Int) {
        self.householdID = householdID
        self.merchantKey = merchantKey
        self.categoryID = categoryID
        self.timesUsed = timesUsed
    }

    enum CodingKeys: String, CodingKey {
        case householdID = "household_id"
        case merchantKey = "merchant_key"
        case categoryID = "category_id"
        case timesUsed = "times_used"
    }
}

extension CategorySuggester {
    /// Suggestion history from the household's past expenses and the server's merchant map.
    ///
    /// The map covers merchants beyond the loaded months. Merchants missing from it (e.g. filed
    /// by hand, or offline before the map caught up) are learned from the transactions.
    public static func build(transactions: [TransactionRow], merchantMap: [MerchantCategoryRow]) -> CategorySuggester {
        var history: [String: [String: Int]] = [:]
        var usage: [String: Int] = [:]
        for row in merchantMap where row.timesUsed > 0 {
            let key = normalize(row.merchantKey)
            guard !key.isEmpty else { continue }
            history[key, default: [:]][row.categoryID.uuidString, default: 0] += row.timesUsed
        }
        // The map already counts these merchants' transactions; don't count them twice.
        let mapped = Set(history.keys)
        for row in transactions where row.kind == .expense {
            guard let category = row.categoryID?.uuidString else { continue }
            usage[category, default: 0] += 1
            if let merchant = row.merchant {
                let key = normalize(merchant)
                if !key.isEmpty, !mapped.contains(key) {
                    history[key, default: [:]][category, default: 0] += 1
                }
            }
        }
        return CategorySuggester(merchantHistory: history, overallUsage: usage)
    }
}
