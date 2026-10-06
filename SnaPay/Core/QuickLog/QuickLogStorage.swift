import Foundation
import SnaPayCore

extension Notification.Name {
    /// Posted in-process when a quick-log intent captured or categorized a payment.
    static let quickLogDidChange = Notification.Name("quickLogDidChange")
}

/// Files the app and its quick-log intents share through the App Group.
///
/// - `quicklog-inbox.json`: payments the automation captured that aren't transactions yet.
///   Intents add and categorize; `TransactionStore` turns categorized ones into transactions.
/// - `quicklog-context.json`: what an intent needs without opening the app (user, household,
///   categories, rates, suggestion history). Written by `TransactionStore` on every save.
/// - `quicklog-log.json`: the last few quick-log events (capture, Live Activity started or
///   ended, and why), shown under Profile → תיעוד בקליק → יומן אבחון.
///
/// All are written with file protection that still allows access while the phone is locked
/// (after the first unlock), since Apple Pay works from the lock screen.
enum QuickLogStorage {
    private static var folder: URL {
        let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static var inboxURL: URL { folder.appendingPathComponent("quicklog-inbox.json") }
    private static var contextURL: URL { folder.appendingPathComponent("quicklog-context.json") }
    private static var logURL: URL { folder.appendingPathComponent("quicklog-log.json") }

    nonisolated struct LogEntry: Codable, Hashable, Sendable {
        let date: Date
        let text: String
    }

    static let logCapacity = 50

    /// Adds a line to the diagnostics log, dropping the oldest beyond `logCapacity`.
    static func log(_ text: String) {
        var entries = loadLog()
        entries.append(LogEntry(date: .now, text: text))
        if entries.count > logCapacity {
            entries.removeFirst(entries.count - logCapacity)
        }
        write(entries, to: logURL)
    }

    /// Oldest first.
    static func loadLog() -> [LogEntry] {
        read([LogEntry].self, from: logURL) ?? []
    }

    static func loadInbox() -> QuickLogInbox {
        read(QuickLogInbox.self, from: inboxURL) ?? QuickLogInbox()
    }

    /// Reads, changes and writes the inbox in one coordinated step, so the app and an intent
    /// can't overwrite each other's changes.
    @discardableResult
    static func updateInbox<T>(_ change: (inout QuickLogInbox) -> T) -> T {
        var result: T?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: inboxURL, options: .forMerging, error: &coordinationError) { url in
            var inbox = read(QuickLogInbox.self, from: url) ?? QuickLogInbox()
            result = change(&inbox)
            write(inbox, to: url)
        }
        if let result { return result }
        // Coordination failed (shouldn't happen for a local file): fall back to a plain update.
        var inbox = loadInbox()
        let fallback = change(&inbox)
        write(inbox, to: inboxURL)
        return fallback
    }

    static func loadContext() -> QuickLogContext? {
        read(QuickLogContext.self, from: contextURL)
    }

    static func saveContext(_ context: QuickLogContext) {
        write(context, to: contextURL)
    }

    /// Sign-out: nothing of this user stays for the intent to use.
    static func erase() {
        try? FileManager.default.removeItem(at: inboxURL)
        try? FileManager.default.removeItem(at: contextURL)
        try? FileManager.default.removeItem(at: logURL)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
