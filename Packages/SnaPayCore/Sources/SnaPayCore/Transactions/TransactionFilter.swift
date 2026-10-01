import Foundation

/// The filters on the Expenses screen. Empty sets mean "any".
public struct TransactionFilter: Equatable, Sendable {
    public var searchText: String
    public var categoryIDs: Set<UUID>
    public var kinds: Set<EntryKind>
    public var userIDs: Set<UUID>
    public var currencies: Set<String>
    public var sources: Set<TransactionSource>
    public var dateRange: DateInterval?
    /// In the main currency.
    public var minAmount: Decimal?
    public var maxAmount: Decimal?

    public init(
        searchText: String = "",
        categoryIDs: Set<UUID> = [],
        kinds: Set<EntryKind> = [],
        userIDs: Set<UUID> = [],
        currencies: Set<String> = [],
        sources: Set<TransactionSource> = [],
        dateRange: DateInterval? = nil,
        minAmount: Decimal? = nil,
        maxAmount: Decimal? = nil
    ) {
        self.searchText = searchText
        self.categoryIDs = categoryIDs
        self.kinds = kinds
        self.userIDs = userIDs
        self.currencies = currencies
        self.sources = sources
        self.dateRange = dateRange
        self.minAmount = minAmount
        self.maxAmount = maxAmount
    }

    /// Number of active filters (search excluded), for the filter button badge.
    public var activeCount: Int {
        [!categoryIDs.isEmpty, !kinds.isEmpty, !userIDs.isEmpty, !currencies.isEmpty, !sources.isEmpty,
         dateRange != nil, minAmount != nil || maxAmount != nil].filter { $0 }.count
    }

    public var isEmpty: Bool {
        activeCount == 0 && searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// - Parameter categoryName: looks up a category's name so search matches it too.
    public func matches(_ transaction: TransactionRow, categoryName: (UUID) -> String? = { _ in nil }) -> Bool {
        if !categoryIDs.isEmpty {
            guard let category = transaction.categoryID, categoryIDs.contains(category) else { return false }
        }
        if !kinds.isEmpty && !kinds.contains(transaction.kind) { return false }
        if !userIDs.isEmpty && !userIDs.contains(transaction.userID) { return false }
        if !currencies.isEmpty && !currencies.contains(transaction.originalCurrency) { return false }
        if !sources.isEmpty && !sources.contains(transaction.source) { return false }
        if let dateRange, !(transaction.occurredAt >= dateRange.start && transaction.occurredAt < dateRange.end) {
            return false
        }
        if let minAmount, transaction.amount < minAmount { return false }
        if let maxAmount, transaction.amount > maxAmount { return false }

        let query = Self.fold(searchText)
        if !query.isEmpty {
            let haystack = [
                transaction.merchant,
                transaction.note,
                transaction.categoryID.flatMap(categoryName),
            ]
            .compactMap { $0 }
            .map(Self.fold)
            guard haystack.contains(where: { $0.contains(query) }) else { return false }
        }
        return true
    }

    public func apply(to transactions: [TransactionRow], categoryName: (UUID) -> String? = { _ in nil }) -> [TransactionRow] {
        transactions.filter { matches($0, categoryName: categoryName) }
    }

    static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
