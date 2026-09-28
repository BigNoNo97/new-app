import Foundation

/// Suggests categories for a merchant in the quick-log card, learning from past choices.
///
/// Suggestions are ranked by how often the user (or their household) picked each category
/// for that merchant; categories never used for the merchant fall back to overall usage,
/// then to the category order the user set.
public struct CategorySuggester: Sendable {
    /// normalized merchant → (category id → times chosen)
    public private(set) var merchantHistory: [String: [String: Int]]
    /// category id → times chosen overall
    public private(set) var overallUsage: [String: Int]

    public init(merchantHistory: [String: [String: Int]] = [:], overallUsage: [String: Int] = [:]) {
        self.merchantHistory = merchantHistory
        self.overallUsage = overallUsage
    }

    /// Records that `categoryID` was chosen for `merchant`.
    public mutating func record(merchant: String, categoryID: String) {
        let key = Self.normalize(merchant)
        if !key.isEmpty {
            merchantHistory[key, default: [:]][categoryID, default: 0] += 1
        }
        overallUsage[categoryID, default: 0] += 1
    }

    /// Up to `count` category ids, most likely first. Only ids in `available` are returned,
    /// and ties keep the order of `available`.
    public func suggest(for merchant: String, available: [String], count: Int = 4) -> [String] {
        let history = merchantHistory[Self.normalize(merchant)] ?? [:]
        let order = Dictionary(available.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let unique = available.filter { seen.insert($0).inserted }
        let ranked = unique.sorted { a, b in
            let ha = history[a, default: 0], hb = history[b, default: 0]
            if ha != hb { return ha > hb }
            let ua = overallUsage[a, default: 0], ub = overallUsage[b, default: 0]
            if ua != ub { return ua > ub }
            return order[a]! < order[b]!
        }
        return Array(ranked.prefix(count))
    }

    /// Lowercases, trims and strips branch numbers / punctuation so that
    /// "SHUFERSAL DEAL #123" and "Shufersal Deal 45" group together, as do
    /// "שופרסל דיל - סניף 12" and "שופרסל דיל".
    public static func normalize(_ merchant: String) -> String {
        let folded = merchant.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var words: [String] = []
        for rawWord in folded.split(whereSeparator: { $0.isWhitespace }) {
            let word = rawWord.filter { $0.isLetter }
            if word.isEmpty { continue }
            if word == "סניף" || word == "branch" { break }
            words.append(word)
        }
        return words.joined(separator: " ")
    }
}
