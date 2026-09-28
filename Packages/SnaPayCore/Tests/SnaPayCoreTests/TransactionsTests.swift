import Foundation
import Testing
@testable import SnaPayCore

private let household = UUID(uuidString: "00000000-0000-0000-0000-0000000000aa")!
private let avi = UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!
private let bella = UUID(uuidString: "00000000-0000-0000-0000-00000000000b")!
private let food = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
private let travel = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!

private let rates = ExchangeRates(
    base: .ils,
    rates: [.usd: Decimal(string: "3.70")!, .eur: Decimal(string: "4.00")!],
    date: Date(timeIntervalSince1970: 0)
)

private func row(
    _ amount: Decimal, kind: EntryKind = .expense, category: UUID? = food, user: UUID = avi,
    at date: Date, merchant: String? = nil, currency: String = "ILS", source: TransactionSource = .manual
) -> TransactionRow {
    TransactionRow(
        householdID: household, userID: user, categoryID: category, kind: kind,
        originalAmount: amount, originalCurrency: currency, amount: amount, currency: "ILS",
        merchant: merchant, occurredAt: date, source: source
    )
}

struct TransactionDraftTests {
    @Test func mainCurrencyExpenseHasNoConversion() throws {
        let draft = TransactionDraft(amount: Decimal(string: "48.9")!, currency: "ILS", categoryID: food, merchant: "  ארומה ")
        let result = try draft.makeRow(householdID: household, userID: avi, mainCurrency: "ILS", rates: nil, cardFeePercent: 3)
        #expect(result.amount == Decimal(string: "48.90")!)
        #expect(result.exchangeRate == 1)
        #expect(result.feeAmount == 0)
        #expect(result.merchant == "ארומה")
        #expect(result.note == nil)
        #expect(!result.isForeign)
    }

    @Test func foreignExpenseAddsCardFee() throws {
        let draft = TransactionDraft(amount: 100, currency: "USD")
        let result = try draft.makeRow(householdID: household, userID: avi, mainCurrency: "ILS", rates: rates, cardFeePercent: Decimal(string: "2.5")!)
        #expect(result.originalAmount == 100)
        #expect(result.originalCurrency == "USD")
        #expect(result.feeAmount == Decimal(string: "9.25")!)
        #expect(result.amount == Decimal(string: "379.25")!)
        #expect(result.currency == "ILS")
        #expect(result.isForeign)
    }

    @Test func foreignIncomeHasNoCardFee() throws {
        let draft = TransactionDraft(kind: .income, amount: 100, currency: "USD")
        let result = try draft.makeRow(householdID: household, userID: avi, mainCurrency: "ILS", rates: rates, cardFeePercent: 3)
        #expect(result.feeAmount == 0)
        #expect(result.amount == 370)
    }

    @Test func foreignWithoutRatesThrows() {
        let draft = TransactionDraft(amount: 10, currency: "EUR")
        #expect(throws: CurrencyConverterError.missingRate(from: .eur, to: .ils)) {
            try draft.makeRow(householdID: household, userID: avi, mainCurrency: "ILS", rates: nil, cardFeePercent: 0)
        }
    }

    @Test func liveConversionLine() {
        let draft = TransactionDraft(amount: 10, currency: "EUR")
        let conversion = draft.conversion(mainCurrency: "ILS", rates: rates, cardFeePercent: 2)
        #expect(conversion?.totalAmount == Decimal(string: "40.80")!)
        #expect(TransactionDraft(amount: 10, currency: "ILS").conversion(mainCurrency: "ILS", rates: rates, cardFeePercent: 2) == nil)
    }

    @Test func editingRoundTrip() throws {
        let original = try TransactionDraft(amount: 25, currency: "USD", categoryID: food, merchant: "Amazon", note: "ספר", occurredAt: date(2026, 9, 1))
            .makeRow(householdID: household, userID: avi, mainCurrency: "ILS", rates: rates, cardFeePercent: 0)
        let draft = TransactionDraft(editing: original)
        #expect(draft.amount == 25)
        #expect(draft.currency == "USD")
        #expect(draft.merchant == "Amazon")
        #expect(draft.note == "ספר")
    }

    @Test func defaultCurrencyFollowsActiveTrip() {
        let trip = Category(id: travel, householdID: household, name: "איטליה", emoji: "✈️", color: "#0EA5E9",
                            tripCurrency: "EUR", tripStartsOn: "2026-10-01", tripEndsOn: "2026-10-10")
        #expect(TransactionDraft.defaultCurrency(mainCurrency: "ILS", categories: [trip], on: date(2026, 10, 10), calendar: .israel) == "EUR")
        #expect(TransactionDraft.defaultCurrency(mainCurrency: "ILS", categories: [trip], on: date(2026, 10, 11), calendar: .israel) == "ILS")
        #expect(TransactionDraft.defaultCurrency(mainCurrency: "ILS", categories: [trip], on: date(2026, 9, 30), calendar: .israel) == "ILS")
    }

    @Test func validity() {
        #expect(!TransactionDraft(amount: 0, currency: "ILS").isValid)
        #expect(TransactionDraft(amount: Decimal(string: "0.01")!, currency: "ILS").isValid)
    }
}

struct AmountInputTests {
    @Test func typing() {
        var text = ""
        for key in ["0", "1", "2", ".", "5", "0", "9"] { text = AmountInput.apply(key: key, to: text) }
        #expect(text == "12.50")
        #expect(AmountInput.decimal(from: text) == Decimal(string: "12.5")!)
    }

    @Test func dotAndBackspace() {
        #expect(AmountInput.apply(key: ".", to: "") == "0.")
        #expect(AmountInput.apply(key: ".", to: "3.") == "3.")
        #expect(AmountInput.apply(key: "⌫", to: "3.5") == "3.")
        #expect(AmountInput.apply(key: "⌫", to: "") == "")
    }

    @Test func limitsIntegerDigits() {
        #expect(AmountInput.apply(key: "1", to: "12345678") == "12345678")
        #expect(AmountInput.decimal(from: "") == 0)
    }
}

struct TransactionSummaryTests {
    let transactions = [
        row(100, at: date(2026, 9, 28, hour: 9), merchant: "סופר"),
        row(50, category: nil, at: date(2026, 9, 28, hour: 18)),
        row(1000, kind: .income, category: nil, at: date(2026, 9, 27)),
        row(30, at: date(2026, 8, 30)),
    ]

    @Test func totalsForInterval() {
        let september = FinancialMonth.containing(date(2026, 9, 28), startDay: 1, calendar: .israel).interval
        let totals = TransactionSummary.totals(transactions, in: september)
        #expect(totals.expenses == 150)
        #expect(totals.income == 1000)
        #expect(totals.balance == 850)
        #expect(totals.count == 3)
    }

    @Test func groupsByDayNewestFirst() {
        let groups = TransactionSummary.groupedByDay(transactions, calendar: .israel)
        #expect(groups.count == 3)
        #expect(groups[0].day == startOfDay(2026, 9, 28))
        #expect(groups[0].transactions.map(\.amount) == [50, 100])
        #expect(groups[0].net == -150)
        #expect(groups[1].net == 1000)
    }

    @Test func byCategoryIncludesUncategorized() {
        let totals = TransactionSummary.byCategory(transactions)
        #expect(totals.count == 2)
        #expect(totals[0].categoryID == food)
        #expect(totals[0].total == 130)
        #expect(totals[1].categoryID == nil)
        #expect(abs(totals[0].share - 130.0 / 180.0) < 0.0001)
    }

    @Test func previousMonthInterval() {
        let september = FinancialMonth.containing(date(2026, 9, 28), startDay: 10, calendar: .israel).interval
        let previous = TransactionSummary.previousInterval(of: september, period: .thisMonth, monthStartDay: 10, calendar: .israel)
        #expect(previous.start == startOfDay(2026, 8, 10))
        #expect(previous.end == september.start)
    }
}

struct TransactionFilterTests {
    let transactions = [
        row(100, at: date(2026, 9, 28), merchant: "Shufersal"),
        row(40, category: travel, user: bella, at: date(2026, 9, 20), merchant: "Trattoria", currency: "EUR"),
        row(1000, kind: .income, category: nil, at: date(2026, 9, 1), source: .recurring),
    ]

    func name(_ id: UUID) -> String? { id == food ? "אוכל ומסעדות" : "טיולים" }

    @Test func emptyFilterMatchesEverything() {
        #expect(TransactionFilter().apply(to: transactions).count == 3)
        #expect(TransactionFilter().isEmpty)
    }

    @Test func searchMatchesMerchantAndCategoryName() {
        #expect(TransactionFilter(searchText: "shuf").apply(to: transactions, categoryName: name).count == 1)
        #expect(TransactionFilter(searchText: "טיול").apply(to: transactions, categoryName: name).count == 1)
    }

    @Test func combinesFilters() {
        let filter = TransactionFilter(kinds: [.expense], userIDs: [bella], currencies: ["EUR"])
        #expect(filter.apply(to: transactions).map(\.merchant) == ["Trattoria"])
        #expect(filter.activeCount == 3)
    }

    @Test func amountAndDateRange() {
        let filter = TransactionFilter(
            dateRange: DateInterval(start: startOfDay(2026, 9, 15), end: startOfDay(2026, 9, 29)),
            minAmount: 50
        )
        #expect(filter.apply(to: transactions).map(\.amount) == [100])
    }

    @Test func categoryFilterExcludesUncategorized() {
        #expect(TransactionFilter(categoryIDs: [food]).apply(to: transactions).count == 1)
        #expect(TransactionFilter(sources: [.recurring]).apply(to: transactions).count == 1)
    }
}

struct RecurringPlannerTests {
    func rule(_ frequency: RecurringRuleRow.Frequency, starts: String, ends: String? = nil, last: String? = nil,
              interval: Int = 1, currency: String = "ILS", active: Bool = true) -> RecurringRuleRow {
        RecurringRuleRow(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            householdID: household, userID: avi, categoryID: food, kind: .expense,
            amount: 50, currency: currency, merchant: "Netflix",
            frequency: frequency, intervalCount: interval,
            startsOn: starts, endsOn: ends, lastGeneratedOn: last, isActive: active
        )
    }

    @Test func backfillsFromStart() {
        let dates = RecurringPlanner.dueDates(for: rule(.monthly, starts: "2026-07-15"), today: date(2026, 9, 28), calendar: .israel)
        #expect(dates == [startOfDay(2026, 7, 15), startOfDay(2026, 8, 15), startOfDay(2026, 9, 15)])
    }

    @Test func continuesAfterLastGenerated() {
        let dates = RecurringPlanner.dueDates(for: rule(.monthly, starts: "2026-07-15", last: "2026-08-15"), today: date(2026, 9, 28), calendar: .israel)
        #expect(dates == [startOfDay(2026, 9, 15)])
    }

    @Test func includesToday() {
        let dates = RecurringPlanner.dueDates(for: rule(.weekly, starts: "2026-09-14", last: "2026-09-21"), today: date(2026, 9, 28, hour: 8), calendar: .israel)
        #expect(dates == [startOfDay(2026, 9, 28)])
    }

    @Test func respectsEndDateAndActiveFlag() {
        #expect(RecurringPlanner.dueDates(for: rule(.monthly, starts: "2026-01-01", ends: "2026-02-15"), today: date(2026, 9, 28), calendar: .israel).count == 2)
        #expect(RecurringPlanner.dueDates(for: rule(.monthly, starts: "2026-01-01", active: false), today: date(2026, 9, 28), calendar: .israel).isEmpty)
        #expect(RecurringPlanner.dueDates(for: rule(.monthly, starts: "2026-10-01"), today: date(2026, 9, 28), calendar: .israel).isEmpty)
    }

    @Test func everyTwoWeeks() {
        let dates = RecurringPlanner.dueDates(for: rule(.weekly, starts: "2026-09-01", interval: 2), today: date(2026, 9, 30), calendar: .israel)
        #expect(dates == [startOfDay(2026, 9, 1), startOfDay(2026, 9, 15), startOfDay(2026, 9, 29)])
    }

    @Test func buildsTransactionsWithStableIDs() throws {
        let transactions = try RecurringPlanner.transactions(
            for: rule(.monthly, starts: "2026-08-15", currency: "USD"), today: date(2026, 9, 28),
            mainCurrency: "ILS", rates: rates, cardFeePercent: 0, calendar: .israel
        )
        #expect(transactions.count == 2)
        #expect(transactions[0].externalID == "rule-20000000-0000-0000-0000-000000000001-2026-08-15")
        #expect(transactions[0].source == .recurring)
        #expect(transactions[0].amount == 185)
        #expect(transactions[0].occurredAt == date(2026, 8, 15, hour: 12))
        #expect(transactions[0].recurringRuleID == UUID(uuidString: "20000000-0000-0000-0000-000000000001")!)
    }
}

struct CSVExporterTests {
    @Test func exportsWithBOMAndEscaping() {
        var t = row(Decimal(string: "12.5")!, at: date(2026, 9, 28), merchant: "Café, \"Nice\"")
        t.note = "=HYPERLINK(\"x\")"
        let csv = CSVExporter.csv([t], categoryName: { _ in "אוכל" }, memberName: { _ in "אבי" }, calendar: .israel)
        #expect(csv.hasPrefix("\u{FEFF}תאריך,סוג,"))
        let line = csv.components(separatedBy: "\r\n")[1]
        #expect(line.hasPrefix("28/09/2026,הוצאה,אוכל,\"Café, \"\"Nice\"\"\",12.50,ILS,12.50,ILS,0.00,"))
        #expect(line.contains("\"'=HYPERLINK(\"\"x\"\")\""))
        #expect(line.hasSuffix(",אבי,ידני"))
    }

    @Test func negativeNumbersAreNotQuoted() {
        #expect(CSVExporter.escape("-12.50") == "-12.50")
        #expect(CSVExporter.escape("-abc") == "'-abc")
    }
}

struct DayStringTests {
    @Test func roundTrip() {
        let day = DayString.date(from: "2026-02-28", calendar: .israel)!
        #expect(DayString.string(from: day, calendar: .israel) == "2026-02-28")
        #expect(DayString.date(from: "2026-02-30", calendar: .israel) == nil)
        #expect(DayString.date(from: "garbage", calendar: .israel) == nil)
    }

    @Test func ratesResponse() throws {
        let json = #"{"base":"ILS","date":"2026-09-28","rates":{"USD":3.7,"eur":4.0}}"#
        let response = try JSONDecoder().decode(ExchangeRatesResponse.self, from: Data(json.utf8))
        let converted = response.exchangeRates(calendar: .israel)
        #expect(converted.rate(from: .usd, to: .ils) == Decimal(string: "3.7")!)
        #expect(converted.rate(from: .eur, to: .ils) == 4)
    }
}

struct DecodingPrecisionTests {
    @Test func transactionAmountsAreRounded() throws {
        let json = """
        {"id":"30000000-0000-0000-0000-000000000001","household_id":"00000000-0000-0000-0000-0000000000aa",
         "user_id":"00000000-0000-0000-0000-00000000000a","category_id":null,"kind":"expense",
         "original_amount":48.9,"original_currency":"USD","exchange_rate":3.7,"fee_amount":4.52,
         "amount":185.45,"currency":"ILS","merchant":"Amazon","note":null,
         "occurred_at":"2026-09-28T09:30:00Z","source":"apple_pay","external_id":"abc",
         "recurring_rule_id":null,"receipt_path":null}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TransactionRow.self, from: Data(json.utf8))
        #expect(decoded.originalAmount == Decimal(string: "48.9")!)
        #expect(decoded.exchangeRate == Decimal(string: "3.7")!)
        #expect(decoded.amount == Decimal(string: "185.45")!)
        #expect(decoded.source == .applePay)
        #expect(decoded.signedAmount == Decimal(string: "-185.45")!)
    }

    @Test func encodesSnakeCaseAndOmitsServerTimestamps() throws {
        let transaction = row(10, at: date(2026, 9, 28))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(transaction)) as! [String: Any]
        #expect(object["household_id"] != nil)
        #expect(object["original_currency"] as? String == "ILS")
        #expect(object["created_at"] == nil)
        #expect(object["source"] as? String == "manual")
    }
}
