import Foundation
import Testing
@testable import SnaPayCore

struct FirestoreJSONTests {
    @Test func writesFixedWidthUTCDates() {
        let date = Date(timeIntervalSince1970: 1_790_000_000.5)
        let text = FirestoreJSON.string(from: date)
        #expect(text.count == 24)
        #expect(text.hasSuffix(".500Z"))
        #expect(FirestoreJSON.date(from: text) == date)
    }

    @Test func datesSortAsText() {
        let earlier = FirestoreJSON.string(from: date(2026, 9, 30, hour: 23))
        let later = FirestoreJSON.string(from: date(2026, 10, 1, hour: 1))
        #expect(earlier < later)
    }

    @Test func readsOffsetsAndMissingFractions() {
        let utc = FirestoreJSON.date(from: "2026-10-01T09:30:00Z")
        #expect(FirestoreJSON.date(from: "2026-10-01T12:30:00+03:00") == utc)
        #expect(FirestoreJSON.date(from: "2026-10-01T09:30:00.123456+00:00")?.timeIntervalSince(utc!) ?? 0 > 0.12)
        #expect(FirestoreJSON.date(from: "yesterday") == nil)
    }

    @Test func transactionsRoundTripThroughDocuments() throws {
        let row = TransactionRow(
            householdID: UUID(), userID: UUID(), categoryID: UUID(), kind: .expense,
            originalAmount: Decimal(string: "64.90")!, originalCurrency: "USD",
            exchangeRate: Decimal(string: "3.71234567")!, feeAmount: Decimal(string: "6.02")!,
            amount: Decimal(string: "246.95")!, currency: "ILS", merchant: "Amazon",
            occurredAt: Date(timeIntervalSince1970: 1_790_000_000.25), source: .applePay, externalID: "applepay-1"
        )
        let document = try FirestoreJSON.encode(row)
        #expect(document["household_id"] as? String == row.householdID.uuidString)
        #expect(document["occurred_at"] as? String == FirestoreJSON.string(from: row.occurredAt))
        #expect(document["receipt_path"] == nil, "nil fields are left out")
        let decoded = try FirestoreJSON.decode(TransactionRow.self, from: document)
        #expect(decoded == row)
    }

    @Test func profileChangesBecomeAPartialUpdate() throws {
        let fields = try FirestoreJSON.encode(ProfileChanges(fullName: "דנה", notifyTips: true))
        #expect(Set(fields.keys) == ["full_name", "notify_tips"])
    }
}

struct HouseholdDocumentTests {
    let me = UUID()
    let partner = UUID()

    func shared() -> HouseholdDocument {
        HouseholdDocument(
            id: UUID(), name: "בית", isShared: true, ownerUID: "uid-partner",
            members: [
                "uid-partner": .init(userID: partner, fullName: "מיכל כהן", joinedAt: date(2026, 9, 1)),
                "uid-me": .init(userID: me, fullName: "דנה לוי", joinedAt: date(2026, 9, 20)),
            ]
        )
    }

    @Test func roundTripsMembersKeyedByUID() throws {
        let household = shared()
        let document = try FirestoreJSON.encode(household)
        let members = document["members"] as? [String: Any]
        #expect(members?.keys.sorted() == ["uid-me", "uid-partner"])
        #expect(try FirestoreJSON.decode(HouseholdDocument.self, from: document) == household)
    }

    @Test func listsActiveMembersOldestFirst() {
        var household = shared()
        #expect(household.householdMembers.map(\.id) == [partner, me])
        #expect(household.householdMembers.first?.isOwner == true)
        household.members["uid-me"]?.removed = true
        #expect(household.householdMembers.map(\.id) == [partner])
        #expect(!household.isActiveMember("uid-me"))
        #expect(household.uid(ofUser: me) == "uid-me")
    }

    @Test func ownershipPassesToTheLongestStandingMember() {
        let household = shared()
        #expect(household.ownerAfterLeaving("uid-me") == "uid-partner")
        #expect(household.ownerAfterLeaving("uid-partner") == "uid-me")
        let alone = HouseholdDocument.personal(uid: "uid-me", userID: me, fullName: "דנה")
        #expect(alone.ownerAfterLeaving("uid-me") == nil)
    }

    @Test func inviteDocumentsAreKeyedByHouseholdAndEmail() throws {
        let household = UUID()
        // Stored dates keep whole milliseconds (and .125 is exact in binary).
        let invite = InviteDocument(householdID: household, email: "dana@example.com", createdAt: Date(timeIntervalSince1970: 1_790_000_000.125),
                                    invitedBy: "uid-partner", inviterName: "מיכל כהן")
        #expect(invite.documentID == "\(household.uuidString)_dana@example.com")
        let document = try FirestoreJSON.encode(invite)
        #expect(try FirestoreJSON.decode(InviteDocument.self, from: document) == invite)
        // The app's own types read the same document.
        #expect(try FirestoreJSON.decode(PendingInvite.self, from: document).inviterFirstName == "מיכל")
        #expect(try FirestoreJSON.decode(HouseholdInviteRow.self, from: document).status == .pending)
    }
}

struct HouseholdMoveTests {
    let old = UUID()
    let new = UUID()

    @Test func matchesCategoriesByNameAndCopiesTheRest() {
        let groceries = CategoryItem(householdID: old, name: "סופר", emoji: "🛒", color: "#2FB36D", sortOrder: 0)
        let trip = CategoryItem(householdID: old, name: "טיול לאיטליה", emoji: "✈️", color: "#5B8DEF", sortOrder: 1, tripCurrency: "EUR", tripStartsOn: "2026-09-20")
        let salary = CategoryItem(householdID: old, name: "משכורת", emoji: "💰", color: "#2FB36D", kind: .income, sortOrder: 2)
        let theirs = CategoryItem(householdID: new, name: " סופר ", emoji: "🛒", color: "#2FB36D", sortOrder: 4)

        let result = HouseholdMove.remapCategories(from: [salary, trip, groceries], into: [theirs], targetHouseholdID: new)
        #expect(result.mapping[groceries.id] == theirs.id)
        #expect(result.copies.count == 2)
        #expect(result.copies.allSatisfy { $0.householdID == new })
        #expect(result.copies.map(\.sortOrder) == [5, 6])
        let tripCopy = result.copies.first { $0.name == trip.name }
        #expect(tripCopy?.tripCurrency == "EUR")
        #expect(result.mapping[trip.id] == tripCopy?.id)
    }

    @Test func movesRowsWithTheirCategories() {
        let category = UUID()
        let mapped = UUID()
        let row = TransactionRow(householdID: old, userID: UUID(), categoryID: category, kind: .expense,
                                 originalAmount: 10, originalCurrency: "ILS", amount: 10, currency: "ILS", occurredAt: .now)
        let moved = HouseholdMove.move([row], to: new, mapping: [category: mapped])
        #expect(moved.first?.householdID == new)
        #expect(moved.first?.categoryID == mapped)
        #expect(moved.first?.id == row.id)

        let rule = RecurringRuleRow(householdID: old, userID: UUID(), categoryID: UUID(), kind: .expense,
                                    amount: 50, currency: "ILS", frequency: .monthly, startsOn: "2026-09-01")
        let movedRule = HouseholdMove.move([rule], to: new, mapping: [:])
        #expect(movedRule.first?.householdID == new)
        #expect(movedRule.first?.categoryID == nil, "a category that didn't come along is cleared")
    }
}

struct RatesParserTests {
    @Test func parsesBankOfIsraelDividingByUnit() throws {
        let json = """
        {"exchangeRates":[
          {"key":"USD","currentExchangeRate":3.7,"currentChange":-0.1,"lastUpdate":"2026-09-28T12:00:00Z"},
          {"key":"JPY","currentExchangeRate":2.46,"unit":100,"lastUpdate":"2026-09-27T12:00:00Z"},
          {"key":"BAD","currentExchangeRate":-1},
          {"key":"toolong","currentExchangeRate":1}
        ]}
        """
        let result = try #require(RatesParser.bankOfIsrael(Data(json.utf8)))
        #expect(result.date == "2026-09-28")
        #expect(result.rates == ["USD": Decimal(string: "3.7")!, "JPY": Decimal(string: "0.0246")!])
    }

    @Test func rejectsUnexpectedPayloads() {
        #expect(RatesParser.bankOfIsrael(Data("{}".utf8)) == nil)
        #expect(RatesParser.bankOfIsrael(Data(#"{"exchangeRates":[]}"#.utf8)) == nil)
        #expect(RatesParser.bankOfIsrael(Data("null".utf8)) == nil)
        #expect(RatesParser.frankfurter(Data(#"{"base":"USD","rates":{"ILS":3.7}}"#.utf8)) == nil)
    }

    @Test func invertsFrankfurterRates() throws {
        let json = #"{"amount":1,"base":"ILS","date":"2026-09-25","rates":{"USD":0.25,"EUR":0.2}}"#
        let result = try #require(RatesParser.frankfurter(Data(json.utf8)))
        #expect(result.rates == ["USD": 4, "EUR": 5])
        #expect(result.date == "2026-09-25")
    }

    @Test func primaryRatesWinWhenMerging() throws {
        let primary = RatesParser.bankOfIsrael(Data(#"{"exchangeRates":[{"key":"USD","currentExchangeRate":3.7,"lastUpdate":"2026-09-28"}]}"#.utf8))
        let fallback = RatesParser.frankfurter(Data(#"{"base":"ILS","date":"2026-09-25","rates":{"USD":0.25,"THB":10}}"#.utf8))
        let merged = try #require(RatesParser.merge(primary: primary, fallback: fallback))
        #expect(merged.rates == ["USD": Decimal(string: "3.7")!, "THB": Decimal(string: "0.1")!])
        #expect(merged.date == "2026-09-28")
        #expect(RatesParser.merge(primary: nil, fallback: fallback)?.date == "2026-09-25")
    }
}
