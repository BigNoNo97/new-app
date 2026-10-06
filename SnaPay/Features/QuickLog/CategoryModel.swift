import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The last resort for a merchant neither the household's history nor `MerchantCatalog` knows:
/// Apple's on-device model picks one of the user's category names. Free and private (nothing
/// leaves the phone), and only on iPhones with Apple Intelligence turned on; elsewhere, or when
/// it takes too long, there's simply no guess.
nonisolated enum CategoryModel {
    static let timeout: Duration = .seconds(4)

    /// One of `names`, or `nil`.
    static func guess(merchant: String, among names: [String]) async -> String? {
        let merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchant.isEmpty, !names.isEmpty else { return nil }
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let prompt = """
        A card payment was made at the merchant "\(merchant)".
        Which of these expense categories fits it best? \(names.map { "\"\($0)\"" }.joined(separator: ", "))
        Answer with the category name exactly as written, and nothing else. If none fits, answer "none".
        """
        let answer: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: "You file card payments into a household budget's categories.")
                return try? await session.respond(to: prompt).content
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return answer.flatMap { match($0, in: names) }
        #else
        return nil
        #endif
    }

    /// The category the answer names: an exact match, else the longest name the answer contains.
    static func match(_ answer: String, in names: [String]) -> String? {
        let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.״׳")))
        if let exact = names.first(where: { $0 == cleaned }) { return exact }
        return names.filter { cleaned.contains($0) }.max { $0.count < $1.count }
    }
}
