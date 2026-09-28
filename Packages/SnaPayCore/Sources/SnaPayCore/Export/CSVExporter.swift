import Foundation

/// Exports transactions to CSV that opens correctly in Excel and Numbers (UTF-8 with BOM,
/// Hebrew headers, day-first dates).
public enum CSVExporter {
    public static let headers = [
        "תאריך", "סוג", "קטגוריה", "בית עסק / תיאור", "סכום", "מטבע",
        "סכום מקורי", "מטבע מקורי", "עמלת המרה", "הערה", "הוזן על ידי", "מקור",
    ]

    public static func csv(
        _ transactions: [TransactionRow],
        categoryName: (UUID) -> String?,
        memberName: (UUID) -> String?,
        calendar: Calendar = .current
    ) -> String {
        var lines = [headers.map(escape).joined(separator: ",")]
        for t in TransactionSummary.sortedNewestFirst(transactions) {
            let fields = [
                date(t.occurredAt, calendar: calendar),
                t.kind == .expense ? "הוצאה" : "הכנסה",
                t.categoryID.flatMap(categoryName) ?? "",
                t.merchant ?? "",
                number(t.amount),
                t.currency,
                number(t.originalAmount),
                t.originalCurrency,
                number(t.feeAmount),
                t.note ?? "",
                memberName(t.userID) ?? "",
                sourceName(t.source),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ field: String) -> String {
        // A leading =, +, - or @ would be run as a formula by spreadsheet apps.
        var value = field
        if let first = value.first, "=+-@".contains(first), Decimal(string: value) == nil {
            value = "'" + value
        }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func number(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    static func date(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    public static func sourceName(_ source: TransactionSource) -> String {
        switch source {
        case .manual: "ידני"
        case .applePay: "Apple Pay"
        case .imported: "ייבוא"
        case .receipt: "קבלה"
        case .recurring: "חיוב קבוע"
        case .openBanking: "בנק"
        }
    }
}

/// Response of the `exchange-rates` edge function.
public struct ExchangeRatesResponse: Codable, Sendable {
    public var base: String
    /// "yyyy-MM-dd"
    public var date: String
    /// Value of one unit of each currency in `base`.
    public var rates: [String: Decimal]

    public init(base: String, date: String, rates: [String: Decimal]) {
        self.base = base
        self.date = date
        self.rates = rates
    }

    public func exchangeRates(calendar: Calendar = .current) -> ExchangeRates {
        ExchangeRates(
            base: CurrencyCode(base),
            rates: Dictionary(rates.map { (CurrencyCode($0.key), $0.value.rounded(scale: 8)) }, uniquingKeysWith: { first, _ in first }),
            date: DayString.date(from: date, calendar: calendar) ?? .now
        )
    }
}
