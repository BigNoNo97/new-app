import Foundation

/// One row read from a bank or credit-card statement export.
public struct StatementRow: Equatable, Sendable {
    public let date: Date
    public let description: String
    /// Negative for money out (expenses), positive for money in (income).
    public let amount: Decimal
}

/// Which column holds what. Either `amount` (signed) or `debit`/`credit` must be set.
public struct StatementColumnMapping: Equatable, Sendable {
    public var date: Int
    public var description: Int
    public var amount: Int?
    public var debit: Int?
    public var credit: Int?

    public init(date: Int, description: Int, amount: Int? = nil, debit: Int? = nil, credit: Int? = nil) {
        self.date = date
        self.description = description
        self.amount = amount
        self.debit = debit
        self.credit = credit
    }
}

public enum BankStatementParserError: Error, Equatable {
    case empty
    case headerNotFound
    case invalidMapping
}

/// Reads CSV exports from Israeli banks (עו"ש) and card issuers.
///
/// Exports differ between banks: some have a few title lines before the header row,
/// some use a signed amount column and some split "חובה" / "זכות". `detectMapping`
/// finds the header row and guesses the mapping; the import screen lets the user fix it.
public enum BankStatementParser {
    static let dateHeaders = ["תאריך", "תאריך ערך", "תאריך עסקה", "תאריך רכישה", "date"]
    static let descriptionHeaders = ["תיאור", "תיאור התנועה", "פרטים", "הפעולה", "שם בית העסק", "שם בית עסק", "description", "merchant"]
    static let amountHeaders = ["סכום", "סכום החיוב", "סכום חיוב", "סכום בש\"ח", "amount"]
    static let debitHeaders = ["חובה", "debit"]
    static let creditHeaders = ["זכות", "credit"]

    /// Splits CSV text into rows of fields. Handles quoted fields, escaped quotes (""),
    /// CRLF line endings, a UTF-8 BOM, and `,`, `;` or tab delimiters (auto-detected).
    public static func parseCSV(_ text: String) -> [[String]] {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        let delimiter = detectDelimiter(body)

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(body).makeIterator()
        var pending: Character? = iterator.next()

        while let char = pending {
            pending = iterator.next()
            if inQuotes {
                if char == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"" where field.isEmpty:
                inQuotes = true
            case delimiter:
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
            .map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.allSatisfy(\.isEmpty) }
    }

    /// Finds the header row and guesses the column mapping.
    /// Returns the index of the header row within `rows`.
    public static func detectMapping(_ rows: [[String]]) throws -> (headerRow: Int, mapping: StatementColumnMapping) {
        guard !rows.isEmpty else { throw BankStatementParserError.empty }
        for (index, row) in rows.prefix(20).enumerated() {
            let normalized = row.map(normalizeHeader)
            guard let date = firstIndex(in: normalized, matching: dateHeaders),
                  let description = firstIndex(in: normalized, matching: descriptionHeaders) else { continue }
            let amount = firstIndex(in: normalized, matching: amountHeaders)
            let debit = firstIndex(in: normalized, matching: debitHeaders)
            let credit = firstIndex(in: normalized, matching: creditHeaders)
            guard amount != nil || debit != nil || credit != nil else { continue }
            return (index, StatementColumnMapping(date: date, description: description, amount: amount, debit: debit, credit: credit))
        }
        throw BankStatementParserError.headerNotFound
    }

    /// Converts data rows (after the header) into statement rows. Rows whose date or
    /// amount can't be read (sub-totals, footers) are skipped.
    ///
    /// - Parameter amountsArePositiveForExpenses: card statements list charges as positive
    ///   numbers; set this to `true` for them so charges come out negative.
    public static func rows(
        from dataRows: [[String]],
        mapping: StatementColumnMapping,
        amountsArePositiveForExpenses: Bool = false,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> [StatementRow] {
        guard mapping.amount != nil || mapping.debit != nil || mapping.credit != nil else {
            throw BankStatementParserError.invalidMapping
        }
        return dataRows.compactMap { fields in
            guard let dateText = field(fields, mapping.date),
                  let date = parseDate(dateText, calendar: calendar) else { return nil }
            let description = field(fields, mapping.description) ?? ""

            let amount: Decimal
            if let column = mapping.amount {
                guard let text = field(fields, column), let value = parseAmount(text) else { return nil }
                amount = amountsArePositiveForExpenses ? -value : value
            } else {
                let debit = mapping.debit.flatMap { field(fields, $0) }.flatMap(parseAmount) ?? 0
                let credit = mapping.credit.flatMap { field(fields, $0) }.flatMap(parseAmount) ?? 0
                guard debit != 0 || credit != 0 else { return nil }
                amount = credit - abs(debit)
            }
            return StatementRow(date: date, description: description, amount: amount)
        }
    }

    /// Parses "1,234.50", "-1,234.50", "(1,234.50)", "₪ 1,234.50", "1234.5-" (trailing minus).
    public static func parseAmount(_ text: String) -> Decimal? {
        var s = text.trimmingCharacters(in: .whitespaces)
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        s = s.filter { $0.isNumber || $0 == "." || $0 == "-" }
        if s.hasSuffix("-") {
            negative.toggle()
            s.removeLast()
        }
        if s.hasPrefix("-") {
            negative.toggle()
            s.removeFirst()
        }
        guard !s.isEmpty, s.allSatisfy({ $0.isNumber || $0 == "." }),
              s.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    /// Parses day-first dates as used in Israel: "23/09/2026", "23.09.26", "23-09-2026",
    /// plus ISO "2026-09-23".
    public static func parseDate(_ text: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        let s = text.trimmingCharacters(in: .whitespaces)
        let parts = s.split(whereSeparator: { $0 == "/" || $0 == "." || $0 == "-" }).map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        let isoOrder = parts[0].count == 4
        let day = isoOrder ? numbers[2] : numbers[0]
        let month = numbers[1]
        var year = isoOrder ? numbers[0] : numbers[2]
        if year < 100 { year += 2000 }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    // MARK: - Helpers

    static func detectDelimiter(_ text: String) -> Character {
        let firstLines = text.split(whereSeparator: \.isNewline).prefix(10).joined(separator: "\n")
        let candidates: [Character] = [",", ";", "\t"]
        return candidates.max { a, b in
            firstLines.filter { $0 == a }.count < firstLines.filter { $0 == b }.count
        } ?? ","
    }

    static func normalizeHeader(_ header: String) -> String {
        header
            .replacingOccurrences(of: "״", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func firstIndex(in headers: [String], matching names: [String]) -> Int? {
        if let exact = headers.firstIndex(where: { names.contains($0) }) { return exact }
        return headers.firstIndex { header in names.contains { !header.isEmpty && header.hasPrefix($0) } }
    }

    static func field(_ fields: [String], _ index: Int) -> String? {
        guard fields.indices.contains(index) else { return nil }
        let value = fields[index]
        return value.isEmpty ? nil : value
    }
}
