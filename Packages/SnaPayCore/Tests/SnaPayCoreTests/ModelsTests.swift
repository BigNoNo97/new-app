import Foundation
import Testing
@testable import SnaPayCore

struct ModelsTests {
    @Test func decodesProfileFromPostgrest() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-00000000000a","full_name":"דנה כהן","main_currency":"ILS",
         "month_start_day":10,"card_fx_fee_percent":2.5,"quick_log_enabled":true,
         "onboarding_completed":false,"active_household_id":null,
         "created_at":"2026-09-28T15:00:00+00:00","updated_at":"2026-09-28T15:00:00+00:00"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(Profile.self, from: Data(json.utf8))
        #expect(profile.firstName == "דנה")
        #expect(profile.monthStartDay == 10)
        #expect(profile.cardFxFeePercent == Decimal(string: "2.5")!)
        #expect(profile.activeHouseholdID == nil)
        #expect(!profile.onboardingCompleted)
    }

    @Test func encodesCategoryRowsWithSnakeCaseKeys() throws {
        let household = UUID()
        let rows = CategoryRow.onboardingRows(chosen: Array(DefaultCategories.expenses.prefix(2)), householdID: household)
        #expect(rows.count == 2 + DefaultCategories.income.count)
        #expect(rows.map(\.sortOrder) == Array(0..<rows.count))
        #expect(rows.last?.kind == .income)

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows[0])) as! [String: Any]
        #expect(Set(object.keys) == ["id", "household_id", "name", "emoji", "color", "kind", "sort_order"])
        #expect(object["kind"] as? String == "expense")
    }

    @Test func customIncomeCategoriesReplaceDefaults() {
        let custom = CategoryDraft(name: "פרילנס", emoji: "💻", colorHex: "#3b82f6", kind: .income)
        let rows = CategoryRow.onboardingRows(chosen: [custom], householdID: UUID())
        #expect(rows.count == 1)
        #expect(rows[0].color == "#3B82F6")
    }

    @Test func supportedCurrenciesAreValidCodes() {
        #expect(SupportedCurrencies.all.first == "ILS")
        #expect(SupportedCurrencies.all.allSatisfy { $0.count == 3 && $0 == $0.uppercased() })
        #expect(Set(SupportedCurrencies.all).count == SupportedCurrencies.all.count)
    }
}
