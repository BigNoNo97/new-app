import Foundation
import Testing
@testable import SnaPayCore

struct CurrencyConverterTests {
    let rates = ExchangeRates(
        base: .ils,
        rates: [.usd: Decimal(string: "3.70")!, .eur: Decimal(string: "4.00")!],
        date: Date(timeIntervalSince1970: 0)
    )

    @Test func convertsForeignAmountAndAddsCardFee() throws {
        let result = try CurrencyConverter.convert(amount: 100, from: .usd, to: .ils, rates: rates, feePercent: Decimal(string: "2.5")!)
        #expect(result.convertedAmount == 370)
        #expect(result.feeAmount == Decimal(string: "9.25")!)
        #expect(result.totalAmount == Decimal(string: "379.25")!)
    }

    @Test func noFeeWhenPayingInMainCurrency() throws {
        let result = try CurrencyConverter.convert(amount: Decimal(string: "48.90")!, from: .ils, to: .ils, rates: rates, feePercent: 3)
        #expect(result.rate == 1)
        #expect(result.feeAmount == 0)
        #expect(result.totalAmount == Decimal(string: "48.90")!)
    }

    @Test func crossRateBetweenTwoForeignCurrencies() throws {
        // 1 EUR = 4.00 ILS, 1 USD = 3.70 ILS → 10 EUR = 10.81 USD
        let result = try CurrencyConverter.convert(amount: 10, from: .eur, to: .usd, rates: rates)
        #expect(result.convertedAmount == Decimal(string: "10.81")!)
    }

    @Test func roundsToAgorot() throws {
        let result = try CurrencyConverter.convert(amount: Decimal(string: "0.333")!, from: .usd, to: .ils, rates: rates)
        #expect(result.convertedAmount == Decimal(string: "1.23")!)
    }

    @Test func missingRateThrows() {
        #expect(throws: CurrencyConverterError.missingRate(from: .gbp, to: .ils)) {
            try CurrencyConverter.convert(amount: 1, from: .gbp, to: .ils, rates: rates)
        }
    }

    @Test func invalidFeeThrows() {
        #expect(throws: CurrencyConverterError.invalidFeePercent) {
            try CurrencyConverter.convert(amount: 1, from: .usd, to: .ils, rates: rates, feePercent: -1)
        }
    }

    @Test func currencyCodeIsUppercased() {
        #expect(CurrencyCode("usd") == .usd)
    }
}
