import Testing
@testable import SnaPayCore

struct CategorySuggesterTests {
    let available = ["food", "groceries", "shopping", "transport", "fun"]

    @Test func fallsBackToUserOrder() {
        let suggester = CategorySuggester()
        #expect(suggester.suggest(for: "New Place", available: available) == ["food", "groceries", "shopping", "transport"])
    }

    @Test func merchantHistoryWins() {
        var suggester = CategorySuggester()
        suggester.record(merchant: "SHUFERSAL DEAL #123", categoryID: "groceries")
        suggester.record(merchant: "Shufersal Deal 45", categoryID: "groceries")
        suggester.record(merchant: "Aroma", categoryID: "food")
        #expect(suggester.suggest(for: "shufersal deal", available: available).first == "groceries")
    }

    @Test func overallUsageBreaksTies() {
        var suggester = CategorySuggester()
        suggester.record(merchant: "Rav Kav", categoryID: "transport")
        suggester.record(merchant: "Gett", categoryID: "transport")
        #expect(suggester.suggest(for: "Unknown", available: available).first == "transport")
    }

    @Test func onlyReturnsAvailableCategoriesWithoutDuplicates() {
        var suggester = CategorySuggester()
        suggester.record(merchant: "Aroma", categoryID: "deleted-category")
        let result = suggester.suggest(for: "Aroma", available: ["food", "food", "fun"], count: 4)
        #expect(result == ["food", "fun"])
    }

    @Test func normalizesHebrewBranchNames() {
        #expect(CategorySuggester.normalize("שופרסל דיל - סניף 12") == "שופרסל דיל")
        #expect(CategorySuggester.normalize("  AROMA  TLV 123 ") == "aroma tlv")
    }
}
