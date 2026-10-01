import Foundation
import Testing
@testable import SnaPayCore

struct PaymentAmountParserTests {
    @Test(arguments: [
        ("₪18.50", "18.5", "ILS"),
        ("\u{200F}18.50\u{00A0}\u{200F}₪", "18.5", "ILS"),
        ("$12.99", "12.99", "USD"),
        ("US$1,234.56", "1234.56", "USD"),
        ("USD 1,234.56", "1234.56", "USD"),
        ("12,99 €", "12.99", "EUR"),
        ("1.234,5 €", "1234.5", "EUR"),
        ("£7", "7", "GBP"),
        ("45 ש\"ח", "45", "ILS"),
    ])
    func parsesFormattedAmounts(text: String, amount: String, currency: String) {
        let result = PaymentAmountParser.parse(text)
        #expect(result == PaymentAmountParser.Result(amount: Decimal(string: amount)!, currency: currency))
    }

    @Test func readsThousandsCommaWithoutDecimals() {
        #expect(PaymentAmountParser.parse("1,234")?.amount == 1234)
    }

    @Test func amountWithoutCurrency() {
        #expect(PaymentAmountParser.parse("42.10") == PaymentAmountParser.Result(amount: Decimal(string: "42.1")!, currency: nil))
    }

    @Test(arguments: ["", "₪", "abc", "0", "₪0.00"])
    func rejectsTextWithoutAPositiveAmount(text: String) {
        #expect(PaymentAmountParser.parse(text) == nil)
    }
}

struct CapturedPaymentTests {
    @Test func externalIDIsStableWithinAMinute() {
        let first = CapturedPayment(amount: Decimal(string: "18.5")!, currency: "ils", merchant: "AROMA TLV 12",
                                    card: "Visa", capturedAt: date(2026, 9, 28, hour: 9), calendar: .israel)
        let again = CapturedPayment(amount: Decimal(string: "18.50")!, currency: "ILS", merchant: "Aroma TLV",
                                    card: "Visa", capturedAt: date(2026, 9, 28, hour: 9).addingTimeInterval(20), calendar: .israel)
        #expect(first.externalID == again.externalID)
        #expect(first.externalID.hasPrefix("applepay-"))
        #expect(first.id != again.id)
    }

    @Test func externalIDDiffersForAnotherPayment() {
        let coffee = CapturedPayment(amount: 18, currency: "ILS", merchant: "Aroma", capturedAt: date(2026, 9, 28), calendar: .israel)
        let secondCoffee = CapturedPayment(amount: 18, currency: "ILS", merchant: "Aroma",
                                           capturedAt: date(2026, 9, 28).addingTimeInterval(600), calendar: .israel)
        let other = CapturedPayment(amount: 19, currency: "ILS", merchant: "Aroma", capturedAt: date(2026, 9, 28), calendar: .israel)
        #expect(coffee.externalID != secondCoffee.externalID)
        #expect(coffee.externalID != other.externalID)
    }

    @Test func cleansInput() {
        let payment = CapturedPayment(amount: Decimal(string: "3.456")!, currency: "usd", merchant: "  Amazon  ", card: " ")
        #expect(payment.amount == Decimal(string: "3.46")!)
        #expect(payment.currency == "USD")
        #expect(payment.merchant == "Amazon")
        #expect(payment.card == nil)
    }
}

struct QuickLogInboxTests {
    let now = date(2026, 9, 28, hour: 9)

    @Test func skipsTheSamePaymentReportedTwice() {
        var inbox = QuickLogInbox()
        let first = inbox.add(CapturedPayment(amount: 18, currency: "ILS", merchant: "Aroma", capturedAt: now))
        // A minute later, so the external ids differ; still the same payment.
        let second = inbox.add(CapturedPayment(amount: 18, currency: "ILS", merchant: "aroma", capturedAt: now.addingTimeInterval(75)))
        #expect(inbox.payments.count == 1)
        #expect(second.id == first.id)
        #expect(inbox.firstCaptureAt == now)
    }

    @Test func keepsTwoRealPayments() {
        var inbox = QuickLogInbox()
        inbox.add(CapturedPayment(amount: 18, currency: "ILS", merchant: "Aroma", capturedAt: now))
        inbox.add(CapturedPayment(amount: 18, currency: "ILS", merchant: "Aroma", capturedAt: now.addingTimeInterval(900)))
        #expect(inbox.payments.count == 2)
    }

    @Test func categorizeAndRemove() {
        var inbox = QuickLogInbox()
        let older = inbox.add(CapturedPayment(amount: 10, currency: "ILS", merchant: "A", capturedAt: now))
        let newer = inbox.add(CapturedPayment(amount: 20, currency: "ILS", merchant: "B", capturedAt: now.addingTimeInterval(300)))
        #expect(inbox.uncategorized.map(\.id) == [newer.id, older.id])

        let category = UUID()
        inbox.categorize(older.id, as: category)
        #expect(inbox.categorized.map(\.id) == [older.id])
        #expect(inbox.uncategorized.map(\.id) == [newer.id])

        inbox.clearCategory(older.id)
        #expect(inbox.categorized.isEmpty)
        inbox.categorize(older.id, as: category)

        inbox.remove([older.id])
        #expect(inbox.payments.map(\.id) == [newer.id])
        #expect(inbox.firstCaptureAt == now)
    }

    @Test func dropsTheOldestBeyondCapacity() {
        var inbox = QuickLogInbox()
        for index in 0...QuickLogInbox.capacity {
            inbox.add(CapturedPayment(amount: Decimal(index + 1), currency: "ILS", merchant: "M", capturedAt: now.addingTimeInterval(Double(index) * 600)))
        }
        #expect(inbox.payments.count == QuickLogInbox.capacity)
        #expect(inbox.payments.first?.amount == 2)
    }

    @Test func roundTripsThroughJSON() throws {
        var inbox = QuickLogInbox()
        inbox.add(CapturedPayment(amount: Decimal(string: "64.9")!, currency: "USD", merchant: "Amazon", card: "Max", capturedAt: now))
        let decoded = try JSONDecoder().decode(QuickLogInbox.self, from: JSONEncoder().encode(inbox))
        #expect(decoded == inbox)
    }
}

struct QuickLogContextTests {
    let household = UUID()
    let user = UUID()

    func category(_ name: String, order: Int, trip: String? = nil, archived: Bool = false) -> CategoryItem {
        CategoryItem(householdID: household, name: name, emoji: "•", color: "#000000", sortOrder: order, isArchived: archived,
                     tripCurrency: trip, tripStartsOn: trip == nil ? nil : "2026-09-20", tripEndsOn: trip == nil ? nil : "2026-10-05")
    }

    func context(_ categories: [CategoryItem], suggester: CategorySuggester = .init(), rates: ExchangeRates? = nil) -> QuickLogContext {
        QuickLogContext(userID: user, householdID: household, mainCurrency: "ILS", cardFeePercent: 2, isEnabled: true,
                        categories: categories, rates: rates, suggester: suggester)
    }

    @Test func keepsOnlyActiveExpenseCategoriesInOrder() {
        let food = category("אוכל", order: 2)
        let groceries = category("סופר", order: 1)
        var salary = category("משכורת", order: 0)
        salary.kind = .income
        let old = category("ישן", order: 3, archived: true)
        #expect(context([food, groceries, salary, old]).categories.map(\.name) == ["סופר", "אוכל"])
    }

    @Test func merchantHistoryRanksFirst() {
        let food = category("אוכל", order: 0)
        let groceries = category("סופר", order: 1)
        var suggester = CategorySuggester()
        suggester.record(merchant: "Shufersal", categoryID: groceries.id.uuidString)
        let shufersal = CapturedPayment(amount: 100, currency: "ILS", merchant: "Shufersal", capturedAt: date(2026, 9, 1))
        #expect(context([food, groceries], suggester: suggester).suggestions(for: shufersal, calendar: .israel).first?.name == "סופר")
    }

    @Test func activeTripInPaymentCurrencyComesFirst() {
        let food = category("אוכל", order: 0)
        let thailand = category("תאילנד", order: 5, trip: "THB")
        let oldTrip = CategoryItem(householdID: household, name: "יוון", emoji: "•", color: "#000000", sortOrder: 6,
                                   tripCurrency: "EUR", tripStartsOn: "2025-07-01", tripEndsOn: "2025-07-10")
        var suggester = CategorySuggester()
        suggester.record(merchant: "7-Eleven", categoryID: food.id.uuidString)
        let quickLog = context([food, thailand, oldTrip], suggester: suggester)

        let inBaht = CapturedPayment(amount: 60, currency: "THB", merchant: "7-Eleven", capturedAt: date(2026, 9, 25))
        #expect(quickLog.suggestions(for: inBaht, calendar: .israel).map(\.name) == ["תאילנד", "אוכל"])

        let inShekels = CapturedPayment(amount: 60, currency: "ILS", merchant: "7-Eleven", capturedAt: date(2026, 9, 25))
        #expect(quickLog.suggestions(for: inShekels, calendar: .israel).map(\.name) == ["אוכל", "תאילנד"])

        let afterTrip = CapturedPayment(amount: 60, currency: "THB", merchant: "7-Eleven", capturedAt: date(2026, 10, 20))
        #expect(quickLog.suggestions(for: afterTrip, calendar: .israel).map(\.name) == ["אוכל"])
    }

    @Test func limitsTheNumberOfSuggestions() {
        let categories = (0..<10).map { category("c\($0)", order: $0) }
        let payment = CapturedPayment(amount: 1, currency: "ILS", merchant: "x")
        #expect(context(categories).suggestions(for: payment, count: 6).count == 6)
    }

    @Test func makesAnApplePayRowWithFee() throws {
        let food = category("אוכל", order: 0)
        let rates = ExchangeRates(base: .ils, rates: [.usd: Decimal(string: "3.7")!], date: .now)
        var payment = CapturedPayment(amount: 10, currency: "USD", merchant: "Amazon", capturedAt: date(2026, 9, 28))
        payment.categoryID = food.id
        let row = try context([food], rates: rates).makeRow(for: payment)
        #expect(row.id == payment.id)
        #expect(row.source == .applePay)
        #expect(row.externalID == payment.externalID)
        #expect(row.categoryID == food.id)
        #expect(row.merchant == "Amazon")
        #expect(row.originalAmount == 10)
        #expect(row.amount == Decimal(string: "37.74")!)
        #expect(row.feeAmount == Decimal(string: "0.74")!)
        #expect(row.occurredAt == payment.capturedAt)
    }

    @Test func contextRoundTripsAndOlderFilesDecode() throws {
        var context = context([category("אוכל", order: 0)])
        context.remindsPendingCapture = false
        let data = try JSONEncoder().encode(context)
        #expect(try JSONDecoder().decode(QuickLogContext.self, from: data) == context)

        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["remindsPendingCapture"] = nil
        let older = try JSONDecoder().decode(QuickLogContext.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.remindsPendingCapture)
    }

    @Test func foreignPaymentWithoutRatesThrows() {
        let payment = CapturedPayment(amount: 10, currency: "USD", merchant: "Amazon")
        #expect(throws: CurrencyConverterError.self) { try context([]).makeRow(for: payment) }
        #expect(context([]).conversion(for: payment) == nil)
    }
}

struct SuggesterBuildTests {
    let household = UUID()
    let user = UUID()
    let food = UUID()
    let groceries = UUID()

    func expense(_ merchant: String, _ category: UUID?) -> TransactionRow {
        TransactionRow(householdID: household, userID: user, categoryID: category, kind: .expense,
                       originalAmount: 10, originalCurrency: "ILS", amount: 10, currency: "ILS",
                       merchant: merchant, occurredAt: .now)
    }

    @Test func learnsFromTransactions() {
        let suggester = CategorySuggester.build(
            transactions: [expense("Aroma 12", food), expense("Aroma", food), expense("Shufersal", groceries), expense("X", nil)],
            merchantMap: []
        )
        #expect(suggester.merchantHistory["aroma"]?[food.uuidString] == 2)
        #expect(suggester.overallUsage[food.uuidString] == 2)
        #expect(suggester.overallUsage[groceries.uuidString] == 1)
    }

    @Test func mapCountsAreNotDoubled() {
        let map = [MerchantCategoryRow(householdID: household, merchantKey: "aroma", categoryID: food, timesUsed: 5)]
        let suggester = CategorySuggester.build(
            transactions: [expense("Aroma", food), expense("Aroma", groceries), expense("Rami Levy", groceries)],
            merchantMap: map
        )
        #expect(suggester.merchantHistory["aroma"] == [food.uuidString: 5])
        #expect(suggester.merchantHistory["rami levy"] == [groceries.uuidString: 1])
    }

    @Test func decodesMerchantMapRows() throws {
        let json = #"[{"household_id":"\#(household.uuidString)","merchant_key":"aroma","category_id":"\#(food.uuidString)","times_used":3,"updated_at":"2026-09-28T10:00:00Z"}]"#
        let rows = try JSONDecoder().decode([MerchantCategoryRow].self, from: Data(json.utf8))
        #expect(rows == [MerchantCategoryRow(householdID: household, merchantKey: "aroma", categoryID: food, timesUsed: 3)])
    }
}
