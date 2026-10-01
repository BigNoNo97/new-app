import Foundation
import SnaPayCore

/// Reference exchange rates, fetched by the app itself (the free Firebase plan has no server
/// functions): Bank of Israel, with Frankfurter filling in other currencies. Kept for the day in
/// the App Group, so the quick-log intent and the app share one fetch.
nonisolated enum ExchangeRatesSource {
    private struct Cached: Codable {
        /// "yyyy-MM-dd" in Israel time: refreshed on the first request of each day.
        var fetchedOn: String
        var rates: ExchangeRatesResponse
    }

    @concurrent static func latest() async throws -> ExchangeRatesResponse {
        let today = Self.today()
        let cached = load()
        if let cached, cached.fetchedOn == today { return cached.rates }

        async let bank = fetch(RatesParser.bankOfIsraelURL)
        async let fallback = fetch(RatesParser.frankfurterURL)
        let primary = (await bank).flatMap { RatesParser.bankOfIsrael($0) }
        let secondary = (await fallback).flatMap { RatesParser.frankfurter($0) }
        guard let fresh = RatesParser.merge(primary: primary, fallback: secondary) else {
            // Offline: yesterday's rates are better than none.
            if let cached { return cached.rates }
            throw URLError(.notConnectedToInternet)
        }
        save(Cached(fetchedOn: today, rates: fresh))
        return fresh
    }

    private static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private static func today() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem") ?? .current
        return DayString.string(from: .now, calendar: calendar)
    }

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.bignono97.snapay")?
            .appendingPathComponent("exchange-rates.json")
    }

    private static func load() -> Cached? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Cached.self, from: data)
    }

    private static func save(_ cached: Cached) {
        guard let fileURL, let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
