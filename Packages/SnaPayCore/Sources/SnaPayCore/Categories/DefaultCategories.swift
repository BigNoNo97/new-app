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
    /// The design's 16 category colors (docs/design/claude-design/design-tokens).
    public static let palette: [String] = [
        "#FF8A3D", "#2FB36D", "#E056B0", "#3B82F6", "#14B8A6", "#8B5CF6", "#F5B301", "#06B6D4",
        "#EF4444", "#A855F7", "#0EA5E9", "#EC4899", "#F59E0B", "#B7791F", "#6366F1", "#A0522D",
    ]

    /// Expense categories offered in onboarding, in display order. All preselected.
    public static let expenses: [CategoryDraft] = [
        CategoryDraft(name: "אוכל ומסעדות", emoji: "🍔", colorHex: "#FF8A3D"),
        CategoryDraft(name: "סופר", emoji: "🛒", colorHex: "#2FB36D"),
        CategoryDraft(name: "קניות", emoji: "🛍️", colorHex: "#E056B0"),
        CategoryDraft(name: "רכב ודלק", emoji: "🚗", colorHex: "#3B82F6"),
        CategoryDraft(name: "תחבורה ציבורית", emoji: "🚌", colorHex: "#14B8A6"),
        CategoryDraft(name: "דיור", emoji: "🏠", colorHex: "#8B5CF6"),
        CategoryDraft(name: "חשבונות", emoji: "💡", colorHex: "#F5B301"),
        CategoryDraft(name: "תקשורת", emoji: "📱", colorHex: "#06B6D4"),
        CategoryDraft(name: "בריאות", emoji: "💊", colorHex: "#EF4444"),
        CategoryDraft(name: "בילויים", emoji: "🎬", colorHex: "#A855F7"),
        CategoryDraft(name: "טיולים", emoji: "✈️", colorHex: "#0EA5E9"),
        CategoryDraft(name: "מתנות", emoji: "🎁", colorHex: "#EC4899"),
        CategoryDraft(name: "ילדים", emoji: "👶", colorHex: "#F59E0B"),
        CategoryDraft(name: "חיות מחמד", emoji: "🐾", colorHex: "#B7791F"),
        CategoryDraft(name: "לימודים", emoji: "📚", colorHex: "#6366F1"),
        CategoryDraft(name: "קפה", emoji: "☕", colorHex: "#A0522D"),
    ]

    /// Income categories, created for every user alongside the chosen expense categories.
    public static let income: [CategoryDraft] = [
        CategoryDraft(name: "משכורת", emoji: "💼", colorHex: "#2FB36D", kind: .income),
        CategoryDraft(name: "מתנה", emoji: "🎁", colorHex: "#EC4899", kind: .income),
        CategoryDraft(name: "הכנסה אחרת", emoji: "💰", colorHex: "#F5B301", kind: .income),
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
