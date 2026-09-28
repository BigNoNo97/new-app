import Foundation

public enum EntryKind: String, Codable, Sendable, CaseIterable {
    case expense
    case income
}

/// A category as the user sets it up in onboarding, before it is saved to the server.
public struct CategoryDraft: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    /// "#RRGGBB"
    public var colorHex: String
    public var kind: EntryKind

    public init(id: UUID = UUID(), name: String, emoji: String, colorHex: String, kind: EntryKind = .expense) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.kind = kind
    }
}

public enum DefaultCategories {
    /// The palette offered in the category editor. Each is readable as a tint in light and dark.
    public static let palette: [String] = [
        "#2FB36D", "#3B82F6", "#F59E0B", "#EF6A5A", "#8B5CF6", "#14B8A6",
        "#EC4899", "#84CC16", "#F97316", "#0EA5E9", "#A16207", "#64748B",
    ]

    /// Expense categories offered in onboarding, in display order. All preselected.
    public static let expenses: [CategoryDraft] = [
        CategoryDraft(name: "אוכל ומסעדות", emoji: "🍔", colorHex: "#EF6A5A"),
        CategoryDraft(name: "סופר", emoji: "🛒", colorHex: "#2FB36D"),
        CategoryDraft(name: "קניות", emoji: "🛍️", colorHex: "#8B5CF6"),
        CategoryDraft(name: "רכב ודלק", emoji: "🚗", colorHex: "#3B82F6"),
        CategoryDraft(name: "תחבורה ציבורית", emoji: "🚌", colorHex: "#0EA5E9"),
        CategoryDraft(name: "דיור", emoji: "🏠", colorHex: "#F59E0B"),
        CategoryDraft(name: "חשבונות", emoji: "💡", colorHex: "#A16207"),
        CategoryDraft(name: "תקשורת", emoji: "📱", colorHex: "#64748B"),
        CategoryDraft(name: "בריאות", emoji: "💊", colorHex: "#14B8A6"),
        CategoryDraft(name: "בילויים", emoji: "🎬", colorHex: "#EC4899"),
        CategoryDraft(name: "טיולים", emoji: "✈️", colorHex: "#0EA5E9"),
        CategoryDraft(name: "מתנות", emoji: "🎁", colorHex: "#F97316"),
        CategoryDraft(name: "ילדים", emoji: "👶", colorHex: "#84CC16"),
        CategoryDraft(name: "חיות מחמד", emoji: "🐾", colorHex: "#A16207"),
        CategoryDraft(name: "לימודים", emoji: "📚", colorHex: "#3B82F6"),
        CategoryDraft(name: "קפה", emoji: "☕", colorHex: "#A16207"),
    ]

    /// Income categories, created for every user alongside the chosen expense categories.
    public static let income: [CategoryDraft] = [
        CategoryDraft(name: "משכורת", emoji: "💼", colorHex: "#2FB36D", kind: .income),
        CategoryDraft(name: "מתנה", emoji: "🎁", colorHex: "#F97316", kind: .income),
        CategoryDraft(name: "הכנסה אחרת", emoji: "💰", colorHex: "#84CC16", kind: .income),
    ]

    /// Emoji grid for the category editor.
    public static let emojiChoices: [String] = [
        "🍔", "🍕", "🍣", "🥗", "☕", "🍺", "🛒", "🛍️", "👗", "👟", "💄", "💇",
        "🚗", "⛽", "🅿️", "🚌", "🚕", "🚲", "✈️", "🏨", "🏖️", "🏠", "🛋️", "🔧",
        "💡", "💧", "🔥", "📱", "💻", "📺", "🎮", "🎬", "🎵", "📚", "🎓", "✏️",
        "💊", "🏥", "🦷", "🏋️", "⚽", "🧘", "👶", "🧸", "🐾", "🎁", "💐", "🎉",
        "💼", "💰", "💳", "🏦", "📈", "🧾", "🛡️", "❤️", "⭐", "📦", "🧹", "🌱",
    ]

    /// Validates a category the user is creating or editing.
    public static func isValid(_ draft: CategoryDraft) -> Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty
            && name.count <= 40
            && !draft.emoji.isEmpty
            && draft.emoji.count <= 2
            && draft.colorHex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }
}
