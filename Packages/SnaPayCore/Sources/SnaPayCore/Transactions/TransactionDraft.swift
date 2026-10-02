import Foundation

/// What the user entered in the add sheet (or what the quick-log card captured).
public struct TransactionDraft: Equatable, Sendable {
    public var kind: EntryKind
    public var amount: Decimal
    public var currency: String
    public var categoryID: UUID?
    public var merchant: String
    public var note: String
    public var occurredAt: Date

    public init(
        kind: EntryKind = .expense,
        amount: Decimal = 0,
        currency: String,
        categoryID: UUID? = nil,
        merchant: String = "",
        note: String = "",
        occurredAt: Date = .now
    ) {
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.categoryID = categoryID
        self.merchant = merchant
        self.note = note
        self.occurredAt = occurredAt
    }

    public var isValid: Bool { amount > 0 && amount < 100_000_000 && currency.count == 3 }

    /// The cost in the main currency, for the live line under the amount. `nil` when paying in
    /// the main currency or when there is no rate yet.
    public func conversion(mainCurrency: String, rates: ExchangeRates?, cardFeePercent: Decimal) -> Conversion? {
        guard currency != mainCurrency, let rates else { return nil }
        return try? CurrencyConverter.convert(
            amount: amount,
            from: CurrencyCode(currency),
            to: CurrencyCode(mainCurrency),
            rates: rates,
            feePercent: kind == .expense ? cardFeePercent : 0
        )
    }

    /// Builds the row to save.
    ///
    /// The card's conversion fee applies only to expenses paid in a foreign currency; income is
    /// converted at the reference rate. Throws `CurrencyConverterError.missingRate` when a
    /// foreign currency has no rate.
    public func makeRow(
        id: UUID = UUID(),
        householdID: UUID,
        userID: UUID,
        mainCurrency: String,
        rates: ExchangeRates?,
        cardFeePercent: Decimal,
        source: TransactionSource = .manual,
        externalID: String? = nil,
        recurringRuleID: UUID? = nil
    ) throws -> TransactionRow {
        let original = amount.rounded(scale: 2)
        var rate: Decimal = 1
        var fee: Decimal = 0
        var total = original

        if currency != mainCurrency {
            guard let rates else {
                throw CurrencyConverterError.missingRate(from: CurrencyCode(currency), to: CurrencyCode(mainCurrency))
            }
            let conversion = try CurrencyConverter.convert(
                amount: original,
                from: CurrencyCode(currency),
                to: CurrencyCode(mainCurrency),
                rates: rates,
                feePercent: kind == .expense ? cardFeePercent : 0
            )
            rate = conversion.rate.rounded(scale: 8)
            fee = conversion.feeAmount
            total = conversion.totalAmount
        }

        return TransactionRow(
            id: id,
            householdID: householdID,
            userID: userID,
            categoryID: categoryID,
            kind: kind,
            originalAmount: original,
            originalCurrency: currency,
            exchangeRate: rate,
            feeAmount: fee,
            amount: total,
            currency: mainCurrency,
            merchant: Self.clean(merchant, limit: 120),
            note: Self.clean(note, limit: 500),
            occurredAt: occurredAt,
            source: source,
            externalID: externalID,
            recurringRuleID: recurringRuleID
        )
    }

    /// A draft pre-filled from an existing transaction, for editing.
    public init(editing row: TransactionRow) {
        self.init(
            kind: row.kind,
            amount: row.originalAmount,
            currency: row.originalCurrency,
            categoryID: row.categoryID,
            merchant: row.merchant ?? "",
            note: row.note ?? "",
            occurredAt: row.occurredAt
        )
    }

    /// The currency a new expense should default to: the active trip's, else the main one.
    public static func defaultCurrency(mainCurrency: String, categories: [CategoryItem], on date: Date, calendar: Calendar = .current) -> String {
        categories.first { $0.isActiveTrip(on: date, calendar: calendar) }?.tripCurrency ?? mainCurrency
    }

    private static func clean(_ text: String, limit: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
    }
}

/// Parses what the user typed in the amount keypad ("1,234.5", "12.", "0.50").
public enum AmountInput {
    /// Applies a keypad key ("0"–"9", ".", "⌫") to the current text, keeping at most two decimals
    /// and eight integer digits.
    public static func apply(key: String, to text: String) -> String {
        switch key {
        case "⌫":
            return String(text.dropLast())
        case ".":
            if text.contains(".") { return text }
            return text.isEmpty ? "0." : text + "."
        default:
            guard key.count == 1, key.first!.isASCII, key.first!.isNumber else { return text }
            if let dot = text.firstIndex(of: ".") {
                if text[text.index(after: dot)...].count >= 2 { return text }
            } else {
                if text == "0" { return key }
                if text.count >= 8 { return text }
            }
            return text + key
        }
    }

    /// The text as shown while typing: "," between thousands, the decimal part as typed
    /// ("15000" → "15,000", "1234.5" → "1,234.5", "12." stays "12.").
    public static func grouped(_ text: String) -> String {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integer = Array(parts.first.map(String.init) ?? "")
        var result = ""
        for (index, digit) in integer.enumerated() {
            if index > 0, (integer.count - index) % 3 == 0 { result.append(",") }
            result.append(digit)
        }
        if parts.count > 1 { result += "." + parts[1] }
        return result
    }

    /// Free typing (a text field, which may show "," groups) reduced to what `apply` would allow:
    /// digits and one ".", up to eight integer digits and two decimals.
    public static func normalized(_ typed: String) -> String {
        typed.reduce(into: "") { text, character in
            let key = String(character)
            guard character.isASCII, character.isNumber || key == "." else { return }
            text = apply(key: key, to: text)
        }
    }

    public static func decimal(from text: String) -> Decimal {
        let cleaned = text.filter { $0.isNumber || $0 == "." }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}
