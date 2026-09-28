import Foundation

/// ISO 4217 currency code, e.g. "ILS", "USD", "EUR".
public struct CurrencyCode: Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { rawValue }

    public static let ils: CurrencyCode = "ILS"
    public static let usd: CurrencyCode = "USD"
    public static let eur: CurrencyCode = "EUR"
    public static let gbp: CurrencyCode = "GBP"
}

/// Exchange rates expressed as "how many units of `base` one unit of the currency is worth".
/// With base ILS: rates["USD"] = 3.70 means 1 USD = 3.70 ILS.
public struct ExchangeRates: Codable, Sendable, Equatable {
    public let base: CurrencyCode
    public let rates: [CurrencyCode: Decimal]
    public let date: Date

    public init(base: CurrencyCode, rates: [CurrencyCode: Decimal], date: Date) {
        self.base = base
        self.rates = rates
        self.date = date
    }

    /// Value of one unit of `currency` in `base`.
    func valueInBase(of currency: CurrencyCode) -> Decimal? {
        if currency == base { return 1 }
        return rates[currency]
    }

    /// Rate to multiply an amount in `from` by to get an amount in `to`.
    public func rate(from: CurrencyCode, to: CurrencyCode) -> Decimal? {
        if from == to { return 1 }
        guard let fromValue = valueInBase(of: from),
              let toValue = valueInBase(of: to),
              toValue != 0 else { return nil }
        return fromValue / toValue
    }
}

/// The result of converting a foreign amount into the user's main currency.
public struct Conversion: Equatable, Sendable {
    public let originalAmount: Decimal
    public let originalCurrency: CurrencyCode
    public let targetCurrency: CurrencyCode
    public let rate: Decimal
    /// Amount in the target currency before the card's conversion fee.
    public let convertedAmount: Decimal
    /// The card's conversion fee, in the target currency.
    public let feeAmount: Decimal
    /// What the user will actually be charged, in the target currency.
    public let totalAmount: Decimal
}

public enum CurrencyConverterError: Error, Equatable {
    case missingRate(from: CurrencyCode, to: CurrencyCode)
    case invalidFeePercent
}

public enum CurrencyConverter {
    /// Converts `amount` from `currency` into `target`.
    ///
    /// The card's conversion fee (`feePercent`, e.g. 2.5 for 2.5%) only applies when the
    /// charge is in a currency other than the target, matching how Israeli card issuers bill.
    /// Amounts are rounded to 2 decimal places (bankers' rounding is avoided: `.plain`).
    public static func convert(
        amount: Decimal,
        from currency: CurrencyCode,
        to target: CurrencyCode,
        rates: ExchangeRates,
        feePercent: Decimal = 0
    ) throws -> Conversion {
        guard feePercent >= 0, feePercent < 100 else {
            throw CurrencyConverterError.invalidFeePercent
        }
        guard let rate = rates.rate(from: currency, to: target) else {
            throw CurrencyConverterError.missingRate(from: currency, to: target)
        }
        let converted = (amount * rate).rounded(scale: 2)
        let fee: Decimal = currency == target ? 0 : (converted * feePercent / 100).rounded(scale: 2)
        return Conversion(
            originalAmount: amount,
            originalCurrency: currency,
            targetCurrency: target,
            rate: rate,
            convertedAmount: converted,
            feeAmount: fee,
            totalAmount: converted + fee
        )
    }
}

extension Decimal {
    public func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }
}
