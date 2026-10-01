import Foundation

/// Reference exchange rates as the value of one unit of each currency in ILS. The app fetches
/// them itself once a day: Bank of Israel first, with Frankfurter (ECB) filling in currencies
/// the Bank doesn't publish.
public enum RatesParser {
    public static let bankOfIsraelURL = URL(string: "https://boi.org.il/PublicApi/GetExchangeRates")!
    public static let frankfurterURL = URL(string: "https://api.frankfurter.app/latest?from=ILS")!

    /// Bank of Israel representative rates:
    /// `{"exchangeRates":[{"key":"USD","currentExchangeRate":3.7,"unit":1,"lastUpdate":"2026-09-28T12:00:00Z"}]}`.
    /// `unit` is how many units the rate is quoted for (JPY is per 100); it may be missing.
    public static func bankOfIsrael(_ data: Data) -> ExchangeRatesResponse? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = body["exchangeRates"] as? [[String: Any]] else { return nil }
        var rates: [String: Decimal] = [:]
        var latest = ""
        for entry in list {
            let key = (entry["key"] as? String ?? "").uppercased()
            guard isCode(key), let rate = number(entry["currentExchangeRate"]), rate > 0 else { continue }
            let unit = number(entry["unit"]).flatMap { $0 > 0 ? $0 : nil } ?? 1
            rates[key] = (rate / unit).rounded(scale: 8)
            let updated = String((entry["lastUpdate"] as? String ?? "").prefix(10))
            if updated > latest { latest = updated }
        }
        guard !rates.isEmpty else { return nil }
        return ExchangeRatesResponse(base: "ILS", date: latest.isEmpty ? DayString.string(from: .now) : latest, rates: rates)
    }

    /// Frankfurter rates from ILS: `{"base":"ILS","date":"2026-09-25","rates":{"USD":0.27}}`
    /// means 1 ILS = 0.27 USD, so 1 USD = 1 / 0.27 ILS.
    public static func frankfurter(_ data: Data) -> ExchangeRatesResponse? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              body["base"] as? String == "ILS",
              let list = body["rates"] as? [String: Any] else { return nil }
        var rates: [String: Decimal] = [:]
        for (code, value) in list {
            guard isCode(code), let perILS = number(value), perILS > 0 else { continue }
            rates[code] = (1 / perILS).rounded(scale: 8)
        }
        guard !rates.isEmpty else { return nil }
        return ExchangeRatesResponse(base: "ILS", date: String((body["date"] as? String ?? "").prefix(10)), rates: rates)
    }

    /// Fallback rates under primary ones (primary wins), so rare currencies are still covered.
    public static func merge(primary: ExchangeRatesResponse?, fallback: ExchangeRatesResponse?) -> ExchangeRatesResponse? {
        guard let primary else { return fallback }
        guard let fallback else { return primary }
        return ExchangeRatesResponse(
            base: primary.base,
            date: primary.date,
            rates: fallback.rates.merging(primary.rates) { _, primaryRate in primaryRate }
        )
    }

    private static func isCode(_ text: String) -> Bool {
        let letters: ClosedRange<Unicode.Scalar> = "A"..."Z"
        return text.unicodeScalars.count == 3 && text.unicodeScalars.allSatisfy { letters.contains($0) }
    }

    /// JSON numbers (or numeric strings) as Decimal, via their text so 3.7 stays 3.7.
    private static func number(_ value: Any?) -> Decimal? {
        guard let value else { return nil }
        switch value {
        case let text as String:
            return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        case let integer as Int:
            return Decimal(integer)
        case let double as Double:
            return Decimal(string: "\(double)", locale: Locale(identifier: "en_US_POSIX"))
        default:
            return nil
        }
    }
}
