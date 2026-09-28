import Foundation

/// A row of `public.households`.
public struct HouseholdRow: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isShared: Bool

    public init(id: UUID, name: String, isShared: Bool) {
        self.id = id
        self.name = name
        self.isShared = isShared
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case isShared = "is_shared"
    }
}

/// An invite someone sent to my email (`public.my_pending_invites()`).
public struct PendingInvite: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var householdID: UUID
    public var inviterName: String
    public var createdAt: Date

    public init(id: UUID, householdID: UUID, inviterName: String, createdAt: Date) {
        self.id = id
        self.householdID = householdID
        self.inviterName = inviterName
        self.createdAt = createdAt
    }

    public var inviterFirstName: String { PersonName.firstName(from: inviterName) }

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case inviterName = "inviter_name"
        case createdAt = "created_at"
    }
}

/// An invite my household sent (`public.household_invites`).
public struct HouseholdInviteRow: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending, accepted, declined, revoked
    }

    public var id: UUID
    public var householdID: UUID
    public var email: String
    public var status: Status
    public var createdAt: Date?

    public init(id: UUID = UUID(), householdID: UUID, email: String, status: Status = .pending, createdAt: Date? = nil) {
        self.id = id
        self.householdID = householdID
        self.email = email
        self.status = status
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case householdID = "household_id"
        case email, status
        case createdAt = "created_at"
    }
}

/// A partial update of `public.profiles`: only the fields that are set are sent.
public struct ProfileChanges: Encodable, Equatable, Sendable {
    public var fullName: String?
    public var monthStartDay: Int?
    public var cardFxFeePercent: Decimal?
    public var quickLogEnabled: Bool?
    public var notifyPartnerActivity: Bool?
    public var notifyBudget: Bool?
    public var notifyMonthlyRecap: Bool?
    public var notifyPendingCapture: Bool?
    public var notifyTips: Bool?

    public init(
        fullName: String? = nil,
        monthStartDay: Int? = nil,
        cardFxFeePercent: Decimal? = nil,
        quickLogEnabled: Bool? = nil,
        notifyPartnerActivity: Bool? = nil,
        notifyBudget: Bool? = nil,
        notifyMonthlyRecap: Bool? = nil,
        notifyPendingCapture: Bool? = nil,
        notifyTips: Bool? = nil
    ) {
        self.fullName = fullName
        self.monthStartDay = monthStartDay
        self.cardFxFeePercent = cardFxFeePercent
        self.quickLogEnabled = quickLogEnabled
        self.notifyPartnerActivity = notifyPartnerActivity
        self.notifyBudget = notifyBudget
        self.notifyMonthlyRecap = notifyMonthlyRecap
        self.notifyPendingCapture = notifyPendingCapture
        self.notifyTips = notifyTips
    }

    public var isEmpty: Bool { self == ProfileChanges() }

    /// Checks the values the database constrains (name ≤ 80, day 1–31, fee 0–20).
    public var isValid: Bool {
        if let fullName, fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fullName.count > 80 { return false }
        if let monthStartDay, !(1...31).contains(monthStartDay) { return false }
        if let cardFxFeePercent, cardFxFeePercent < 0 || cardFxFeePercent > 20 { return false }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case monthStartDay = "month_start_day"
        case cardFxFeePercent = "card_fx_fee_percent"
        case quickLogEnabled = "quick_log_enabled"
        case notifyPartnerActivity = "notify_partner_activity"
        case notifyBudget = "notify_budget"
        case notifyMonthlyRecap = "notify_monthly_recap"
        case notifyPendingCapture = "notify_pending_capture"
        case notifyTips = "notify_tips"
    }
}
