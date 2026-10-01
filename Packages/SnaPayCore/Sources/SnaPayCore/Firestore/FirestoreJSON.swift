import Foundation

/// Firestore documents are the models' JSON: the field names of the old database columns
/// (`household_id`, `occurred_at`…), dates as fixed-width UTC ISO 8601 strings, and amounts as
/// numbers.
///
/// Fixed-width UTC dates sort and compare as text, so range queries on `occurred_at` work
/// without Firestore timestamps, and the same models decode documents, the local cache and test
/// fixtures.
public enum FirestoreJSON {
    public enum Failure: Error {
        case notAnObject
    }

    public static func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.notAnObject
        }
        return object
    }

    public static func decode<T: Decodable>(_ type: T.Type, from document: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: document)
        return try decoder.decode(type, from: data)
    }

    /// "2026-10-01T09:30:00.000Z"
    public static func string(from date: Date) -> String {
        // Whole milliseconds, split off before taking components (nanosecond components drift).
        let totalMilliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let wholeSeconds = (totalMilliseconds / 1000).rounded(.down)
        let milliseconds = Int(totalMilliseconds - wholeSeconds * 1000)
        let c = utcCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: wholeSeconds)
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, milliseconds
        )
    }

    /// Reads "yyyy-MM-ddTHH:mm:ss", optionally with a fraction and "Z" or "+00:00" — what this
    /// type writes, and what the old server sent.
    public static func date(from string: String) -> Date? {
        let scalars = Array(string.utf8)
        guard scalars.count >= 19 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            Int(String(decoding: scalars[range], as: UTF8.self))
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19) else { return nil }
        var nanosecond = 0
        var index = 19
        if index < scalars.count, scalars[index] == UInt8(ascii: ".") {
            index += 1
            var digits = 0
            var fraction = 0
            while index < scalars.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(scalars[index]) {
                if digits < 9 {
                    fraction = fraction * 10 + Int(scalars[index] - UInt8(ascii: "0"))
                    digits += 1
                }
                index += 1
            }
            nanosecond = fraction * Int(pow(10.0, Double(9 - digits)))
        }
        var offsetSeconds = 0
        if index < scalars.count, scalars[index] == UInt8(ascii: "+") || scalars[index] == UInt8(ascii: "-"),
           scalars.count >= index + 6,
           let hours = number(index + 1..<index + 3), let minutes = number(index + 4..<index + 6) {
            offsetSeconds = (hours * 3600 + minutes * 60) * (scalars[index] == UInt8(ascii: "-") ? -1 : 1)
        }
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second, nanosecond: nanosecond
        )
        return utcCalendar.date(from: components)?.addingTimeInterval(TimeInterval(-offsetSeconds))
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(FirestoreJSON.string(from: date))
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = FirestoreJSON.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable date \(text)")
            }
            return date
        }
        return decoder
    }
}
