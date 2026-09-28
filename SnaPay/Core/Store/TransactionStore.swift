import Foundation
import Observation
import SnaPayCore

/// A change made on this device that the server hasn't confirmed yet.
nonisolated enum PendingChange: Codable, Sendable, Equatable {
    case save(TransactionRow)
    case delete(UUID)
}

/// What's kept on disk so the app opens instantly and works offline.
nonisolated struct StoreSnapshot: Codable, Sendable {
    var categories: [CategoryItem]
    var members: [HouseholdMember]
    var transactions: [TransactionRow]
    var rates: ExchangeRates?
    var outbox: [PendingChange]
    var savedAt: Date
}

enum StoreError: Error, Equatable {
    case missingRate(String)
    case offline
    case rejected
}

/// The household's data for the signed-in user.
///
/// The server is the source of truth. The store keeps the last ~13 months in memory and on disk,
/// applies changes locally first, and queues them (outbox) until the server confirms, so adding
/// an expense works without a connection.
@Observable
final class TransactionStore {
    private(set) var categories: [CategoryItem] = []
    private(set) var members: [HouseholdMember] = []
    /// Newest first.
    private(set) var transactions: [TransactionRow] = []
    private(set) var rates: ExchangeRates?
    private(set) var isRefreshing = false
    private(set) var hasOlderTransactions = true
    private(set) var profile: Profile
    /// Set when the last sync failed for a reason other than being offline.
    var syncProblem: StoreError?

    let userID: UUID
    let householdID: UUID

    private let repository: DataRepository
    private var outbox: [PendingChange] = []
    private var oldestLoaded: Date
    private let calendar: Calendar

    static let historyDays = 400
    static let olderPageSize = 200

    init(profile: Profile, userID: UUID, householdID: UUID, repository: DataRepository, calendar: Calendar = .current) {
        self.profile = profile
        self.userID = userID
        self.householdID = householdID
        self.repository = repository
        self.calendar = calendar
        oldestLoaded = calendar.date(byAdding: .day, value: -Self.historyDays, to: .now)!
    }

    // MARK: Derived data

    var mainCurrency: String { profile.mainCurrency }
    var pendingCount: Int { outbox.count }
    var isShared: Bool { members.count > 1 }

    func categories(for kind: EntryKind) -> [CategoryItem] {
        categories.filter { $0.kind == kind && !$0.isArchived }
    }

    func category(_ id: UUID?) -> CategoryItem? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func memberName(_ id: UUID) -> String? {
        members.first { $0.id == id }?.firstName
    }

    var trips: [CategoryItem] { categories.filter(\.isTrip) }

    var activeTrip: CategoryItem? {
        categories.first { $0.isActiveTrip(on: .now, calendar: calendar) }
    }

    func canEdit(_ transaction: TransactionRow) -> Bool {
        transaction.userID == userID
    }

    func interval(for period: ReportingPeriod) -> DateInterval {
        period.interval(now: .now, monthStartDay: profile.monthStartDay, calendar: calendar)
    }

    func transactions(in interval: DateInterval) -> [TransactionRow] {
        transactions.filter { $0.occurredAt >= interval.start && $0.occurredAt < interval.end }
    }

    func newDraft(kind: EntryKind = .expense) -> TransactionDraft {
        TransactionDraft(
            kind: kind,
            currency: kind == .expense
                ? TransactionDraft.defaultCurrency(mainCurrency: mainCurrency, categories: categories, on: .now, calendar: calendar)
                : mainCurrency
        )
    }

    // MARK: Loading

    /// Shows the saved snapshot immediately, then syncs with the server.
    func start() async {
        loadSnapshot()
        await refresh()
        await generateRecurring()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await flushOutbox()
        do {
            categories = try await repository.fetchCategories(householdID: householdID)
            members = try await repository.fetchMembers(householdID: householdID)
            let fetched = try await repository.fetchTransactions(householdID: householdID, since: oldestLoaded)
            transactions = TransactionSummary.sortedNewestFirst(applyingOutbox(to: fetched))
            if rates == nil || !calendar.isDateInToday(rates!.date) {
                rates = (try? await repository.fetchExchangeRates()) ?? rates
            }
            if syncProblem == .offline { syncProblem = nil }
        } catch {
            syncProblem = Self.isOffline(error) ? .offline : .rejected
        }
        saveSnapshot()
    }

    func loadOlder() async {
        guard hasOlderTransactions else { return }
        do {
            let older = try await repository.fetchTransactions(householdID: householdID, before: oldestLoaded, limit: Self.olderPageSize)
            hasOlderTransactions = older.count == Self.olderPageSize
            if let last = older.last { oldestLoaded = last.occurredAt }
            let known = Set(transactions.map(\.id))
            transactions = TransactionSummary.sortedNewestFirst(transactions + older.filter { !known.contains($0.id) })
        } catch {
            syncProblem = Self.isOffline(error) ? .offline : .rejected
        }
    }

    private func ensureRates() async throws -> ExchangeRates {
        if let rates { return rates }
        do {
            let fetched = try await repository.fetchExchangeRates()
            rates = fetched
            return fetched
        } catch {
            throw StoreError.offline
        }
    }

    // MARK: Changes

    /// Saves a new transaction (or edits `existing`) from the add sheet.
    @discardableResult
    func save(_ draft: TransactionDraft, editing existing: TransactionRow? = nil) async throws -> TransactionRow {
        var rates = self.rates
        if draft.currency != mainCurrency {
            rates = try await ensureRates()
        }
        var row: TransactionRow
        do {
            row = try draft.makeRow(
                id: existing?.id ?? UUID(),
                householdID: householdID,
                userID: userID,
                mainCurrency: mainCurrency,
                rates: rates,
                cardFeePercent: profile.cardFxFeePercent,
                source: existing?.source ?? .manual,
                externalID: existing?.externalID,
                recurringRuleID: existing?.recurringRuleID
            )
        } catch {
            throw StoreError.missingRate(draft.currency)
        }
        row.createdAt = existing?.createdAt ?? .now
        upsertLocally(row)
        outbox.append(.save(row))
        saveSnapshot()
        await flushOutbox()
        return row
    }

    func delete(_ transaction: TransactionRow) async {
        guard canEdit(transaction) else { return }
        transactions.removeAll { $0.id == transaction.id }
        outbox.append(.delete(transaction.id))
        saveSnapshot()
        await flushOutbox()
    }

    /// Creates a recurring rule starting on the draft's date and generates what's already due.
    func createRecurring(
        from draft: TransactionDraft,
        frequency: RecurringRuleRow.Frequency,
        interval: Int,
        endsOn: Date?
    ) async throws {
        let merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = RecurringRuleRow(
            householdID: householdID,
            userID: userID,
            categoryID: draft.categoryID,
            kind: draft.kind,
            amount: draft.amount.rounded(scale: 2),
            currency: draft.currency,
            merchant: merchant.isEmpty ? nil : merchant,
            note: note.isEmpty ? nil : note,
            frequency: frequency,
            intervalCount: max(interval, 1),
            startsOn: DayString.string(from: draft.occurredAt, calendar: calendar),
            endsOn: endsOn.map { DayString.string(from: $0, calendar: calendar) }
        )
        do {
            try await repository.saveRecurringRule(rule)
        } catch {
            throw Self.isOffline(error) ? StoreError.offline : StoreError.rejected
        }
        await generateRecurring()
    }

    /// Creates the transactions this user's recurring rules owe up to today.
    func generateRecurring() async {
        guard let rules = try? await repository.fetchRecurringRules(userID: userID), !rules.isEmpty else { return }
        var created = false
        for var rule in rules {
            let needsRates = rule.currency != mainCurrency
            let rates = needsRates ? (try? await ensureRates()) : self.rates
            if needsRates && rates == nil { continue }
            guard let rows = try? RecurringPlanner.transactions(
                for: rule, today: .now, mainCurrency: mainCurrency, rates: rates,
                cardFeePercent: profile.cardFxFeePercent, calendar: calendar
            ), let last = rows.last else { continue }
            do {
                try await repository.insertIgnoringDuplicates(rows)
                rule.lastGeneratedOn = DayString.string(from: last.occurredAt, calendar: calendar)
                try await repository.saveRecurringRule(rule)
                created = true
            } catch {
                syncProblem = Self.isOffline(error) ? .offline : .rejected
                return
            }
        }
        if created { await refresh() }
    }

    func createTrip(name: String, emoji: String, currency: String, startsOn: Date, endsOn: Date) async throws {
        let trip = CategoryItem(
            householdID: householdID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: emoji,
            color: "#0EA5E9",
            kind: .expense,
            sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 1,
            tripCurrency: currency,
            tripStartsOn: DayString.string(from: startsOn, calendar: calendar),
            tripEndsOn: DayString.string(from: endsOn, calendar: calendar)
        )
        do {
            try await repository.saveCategory(trip)
        } catch {
            throw Self.isOffline(error) ? StoreError.offline : StoreError.rejected
        }
        categories.append(trip)
        saveSnapshot()
    }

    // MARK: Sync

    private func flushOutbox() async {
        sync: while let change = outbox.first {
            do {
                switch change {
                case .save(let row): try await repository.saveTransactions([row])
                case .delete(let id): try await repository.deleteTransaction(id: id)
                }
                outbox.removeFirst()
            } catch let error where Self.isOffline(error) {
                syncProblem = .offline
                break sync
            } catch {
                // The server refused it (e.g. permissions): drop it so the queue can't jam.
                outbox.removeFirst()
                syncProblem = .rejected
            }
        }
        saveSnapshot()
    }

    private func upsertLocally(_ row: TransactionRow) {
        transactions.removeAll { $0.id == row.id }
        transactions = TransactionSummary.sortedNewestFirst(transactions + [row])
    }

    private func applyingOutbox(to rows: [TransactionRow]) -> [TransactionRow] {
        var byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for change in outbox {
            switch change {
            case .save(let row): byID[row.id] = row
            case .delete(let id): byID[id] = nil
            }
        }
        return Array(byID.values)
    }

    static func isOffline(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                    .cannotFindHost, .dataNotAllowed, .internationalRoamingOff].contains(urlError.code)
        }
        return (error as? StoreError) == .offline || (error as? AuthFailure) == .network
    }

    // MARK: Snapshot

    private var snapshotURL: URL {
        let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("snapshot-\(userID.uuidString).json")
    }

    private func loadSnapshot() {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(StoreSnapshot.self, from: data) else { return }
        categories = snapshot.categories
        members = snapshot.members
        transactions = TransactionSummary.sortedNewestFirst(snapshot.transactions)
        rates = snapshot.rates
        outbox = snapshot.outbox
    }

    private func saveSnapshot() {
        let snapshot = StoreSnapshot(
            categories: categories, members: members, transactions: transactions,
            rates: rates, outbox: outbox, savedAt: .now
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Removes this user's saved data from the device (sign-out).
    func eraseLocalData() {
        try? FileManager.default.removeItem(at: snapshotURL)
    }
}
