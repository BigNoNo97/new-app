import Foundation

/// A row of `public.profiles`.
public struct Profile: Codable, Equatable, Sendable {
    public var id: UUID
    public var fullName: String
    public var mainCurrency: String
    public var monthStartDay: Int
    public var cardFxFeePercent: Decimal
    public var quickLogEnabled: Bool
    public var onboardingCompleted: Bool
    public var activeHouseholdID: UUID?
    public var createdAt: Date?
    // Notifications (settings screen). Missing in older cached profiles, so decoded with defaults.
    public var notifyPartnerActivity = true
    public var notifyBudget = true
    public var notifyMonthlyRecap = true
    public var notifyPendingCapture = true
    public var notifyTips = false

    public init(
        id: UUID,
        fullName: String,
        mainCurrency: String = "ILS",
        monthStartDay: Int = 1,
        cardFxFeePercent: Decimal = 0,
        quickLogEnabled: Bool = true,
        onboardingCompleted: Bool = false,
        activeHouseholdID: UUID? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.mainCurrency = mainCurrency
        self.monthStartDay = monthStartDay
        self.cardFxFeePercent = cardFxFeePercent
        self.quickLogEnabled = quickLogEnabled
        self.onboardingCompleted = onboardingCompleted
        self.activeHouseholdID = activeHouseholdID
        self.createdAt = createdAt
    }

    public var firstName: String { PersonName.firstName(from: fullName) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fullName = try c.decode(String.self, forKey: .fullName)
        mainCurrency = try c.decode(String.self, forKey: .mainCurrency)
        monthStartDay = try c.decode(Int.self, forKey: .monthStartDay)
        cardFxFeePercent = try c.decodeDecimal(forKey: .cardFxFeePercent, scale: 2)
        quickLogEnabled = try c.decode(Bool.self, forKey: .quickLogEnabled)
        onboardingCompleted = try c.decode(Bool.self, forKey: .onboardingCompleted)
        activeHouseholdID = try c.decodeIfPresent(UUID.self, forKey: .activeHouseholdID)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        notifyPartnerActivity = try c.decodeIfPresent(Bool.self, forKey: .notifyPartnerActivity) ?? true
        notifyBudget = try c.decodeIfPresent(Bool.self, forKey: .notifyBudget) ?? true
        notifyMonthlyRecap = try c.decodeIfPresent(Bool.self, forKey: .notifyMonthlyRecap) ?? true
        notifyPendingCapture = try c.decodeIfPresent(Bool.self, forKey: .notifyPendingCapture) ?? true
        notifyTips = try c.decodeIfPresent(Bool.self, forKey: .notifyTips) ?? false
    }

    /// Applies the fields a settings change carries.
    public mutating func apply(_ changes: ProfileChanges) {
        if let value = changes.fullName { fullName = value }
        if let value = changes.monthStartDay { monthStartDay = value }
        if let value = changes.cardFxFeePercent { cardFxFeePercent = value }
        if let value = changes.quickLogEnabled { quickLogEnabled = value }
        if let value = changes.notifyPartnerActivity { notifyPartnerActivity = value }
        if let value = changes.notifyBudget { notifyBudget = value }
        if let value = changes.notifyMonthlyRecap { notifyMonthlyRecap = value }
        if let value = changes.notifyPendingCapture { notifyPendingCapture = value }
        if let value = changes.notifyTips { notifyTips = value }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case mainCurrency = "main_currency"
        case monthStartDay = "month_start_day"
        case cardFxFeePercent = "card_fx_fee_percent"
        case quickLogEnabled = "quick_log_enabled"
        case onboardingCompleted = "onboarding_completed"
        case activeHouseholdID = "active_household_id"
        case createdAt = "created_at"
        case notifyPartnerActivity = "notify_partner_activity"
        case notifyBudget = "notify_budget"
        case notifyMonthlyRecap = "notify_monthly_recap"
        case notifyPendingCapture = "notify_pending_capture"
        case notifyTips = "notify_tips"
    }
}

/// A row to insert into (or upsert on) `public.categories`.
public struct CategoryRow: Codable, Equatable, Sendable {
    public var id: UUID
    public var householdID: UUID
    public var name: String
    public var emoji: String
    public var color: String
    public var kind: EntryKind
    public var sortOrder: Int

    public init(draft: CategoryDraft, householdID: UUID, sortOrder: Int) {
        self.id = draft.id
        self.householdID = householdID
        self.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.emoji = draft.emoji
        self.color = draft.colorHex.uppercased()
        self.kind = draft.kind
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case name, emoji, color, kind
        case sortOrder = "sort_order"
    }

    /// Rows for the categories chosen in onboarding, keeping their order, followed by the
    /// income categories.
    public static func onboardingRows(chosen: [CategoryDraft], householdID: UUID) -> [CategoryRow] {
        let expenses = chosen.filter { $0.kind == .expense }
        let incomes = chosen.filter { $0.kind == .income }
        let income = incomes.isEmpty ? DefaultCategories.income : incomes
        return (expenses + income).enumerated().map { index, draft in
            CategoryRow(draft: draft, householdID: householdID, sortOrder: index)
        }
    }
}

public enum SupportedCurrencies {
    /// Main currencies offered at sign-up and for trips, most common for Israeli users first.
    public static let all: [String] = [
        "ILS", "USD", "EUR", "GBP", "RUB", "UAH", "CHF", "JPY", "CAD", "AUD", "THB", "TRY",
        "CZK", "PLN", "HUF", "GEL", "AED", "EGP", "JOD", "CNY", "INR", "SEK", "NOK", "DKK",
    ]
}
