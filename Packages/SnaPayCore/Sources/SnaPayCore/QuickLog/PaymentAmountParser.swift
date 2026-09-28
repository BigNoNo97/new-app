import Foundation

/// Reads an amount the Shortcuts automation passed as text ("₪18.50", "18,50 €", "USD 1,234.56").
///
/// The quick-log intent normally receives a currency amount; this is the fallback for
/// automations that pass the amount as text, formatted in whatever locale the phone uses.
public enum PaymentAmountParser {
    public struct Result: Equatable, Sendable {
        public var amount: Decimal
        /// `nil` when the text names no currency.
        public var currency: String?
    }

    private static let symbols: [(String, String)] = [
        // Longer symbols first, so "US$" isn't read as "$".
        ("US$", "USD"), ("ש\"ח", "ILS"), ("ש״ח", "ILS"), ("שח", "ILS"),
        ("₪", "ILS"), ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("₽", "RUB"), ("฿", "THB"), ("¥", "JPY"),
    ]

    public static func parse(_ text: String) -> Result? {
        let cleaned = String(text.unicodeScalars.filter { !isFormatting($0) })
        let currency = isoCode(in: cleaned) ?? symbols.first { cleaned.contains($0.0) }?.1
        guard let amount = number(in: cleaned), amount > 0 else { return nil }
        return Result(amount: amount.rounded(scale: 2), currency: currency)
    }

    /// Bidi marks and non-breaking spaces that number formatting adds around Hebrew text.
    private static func isFormatting(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069, 0x00A0, 0x202F: true
        default: false
        }
    }

    private static func isoCode(in text: String) -> String? {
        var letters = ""
        for character in text + " " {
            if character.isASCII, character.isUppercase {
                letters.append(character)
            } else {
                if letters.count == 3, SupportedCurrencies.all.contains(letters) { return letters }
                letters = ""
            }
        }
        return nil
    }

    /// The first run of digits and separators, with "," or "." as the decimal point: whichever
    /// comes last when both appear, and a lone "," only when 1–2 digits follow it.
    private static func number(in text: String) -> Decimal? {
        guard let start = text.firstIndex(where: { $0.isASCII && $0.isNumber }) else { return nil }
        let run = text[start...].prefix { ($0.isASCII && $0.isNumber) || $0 == "," || $0 == "." || $0 == "'" || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
            .filter { $0 != "'" && $0 != " " }
            .trimmingCharacters(in: CharacterSet(charactersIn: ",."))
        let lastComma = run.lastIndex(of: ",")
        let lastDot = run.lastIndex(of: ".")
        var decimalSeparator: Character?
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            decimalSeparator = comma > dot ? "," : "."
        case let (comma?, nil):
            let digitsAfter = run[run.index(after: comma)...].count
            let commas = run.filter { $0 == "," }.count
            decimalSeparator = commas == 1 && digitsAfter <= 2 ? "," : nil
        case (nil, .some):
            decimalSeparator = run.filter { $0 == "." }.count == 1 ? "." : nil
        case (nil, nil):
            decimalSeparator = nil
        }
        var normalized = ""
        var seenDecimal = false
        for (index, character) in zip(run.indices, run) {
            if character.isNumber {
                normalized.append(character)
            } else if character == decimalSeparator,
                      index == (decimalSeparator == "," ? lastComma : lastDot), !seenDecimal {
                normalized.append(".")
                seenDecimal = true
            }
        }
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
