import Foundation
import SnaPayCore

/// In-memory auth and data for UI tests and previews. Any email/password pair signs up;
/// "wrong@example.com" fails to log in so tests can exercise error states.
final class InMemoryServices: AuthServicing, AccountRepository, DataRepository {
    private var profiles: [UUID: Profile] = [:]
    private var categories: [CategoryItem] = []
    private var transactions: [UUID: TransactionRow] = [:]
    private var rules: [UUID: RecurringRuleRow] = [:]
    private var merchantMap: [MerchantCategoryRow] = []
    private var passwords: [String: (UUID, String)] = [:]
    private(set) var savedCategories: [CategoryRow] = []
    private var currentUser: UUID?

    func restoreSession() async -> UUID? { currentUser }

    func signUp(fullName: String, email: String, password: String, mainCurrency: String) async throws -> SignUpOutcome {
        let key = CredentialsValidator.normalizedEmail(email)
        guard passwords[key] == nil else { throw AuthFailure.emailAlreadyRegistered }
        let id = UUID()
        passwords[key] = (id, password)
        profiles[id] = Profile(id: id, fullName: fullName, mainCurrency: mainCurrency, activeHouseholdID: UUID(), createdAt: .now)
        currentUser = id
        return .signedIn
    }

    func logIn(email: String, password: String) async throws -> UUID {
        let key = CredentialsValidator.normalizedEmail(email)
        if key == "wrong@example.com" { throw AuthFailure.invalidCredentials }
        if let existing = passwords[key] {
            guard existing.1 == password else { throw AuthFailure.invalidCredentials }
            currentUser = existing.0
            return existing.0
        }
        // Unknown users log in as a returning user who already finished onboarding.
        let id = UUID()
        passwords[key] = (id, password)
        profiles[id] = Profile(id: id, fullName: "משתמש בדיקה", onboardingCompleted: true, activeHouseholdID: UUID(), createdAt: .now)
        currentUser = id
        return id
    }

    func sendPasswordReset(email: String) async throws {}

    func handleRedirect(_ url: URL) async throws -> (AuthRedirect, UUID) {
        guard let user = currentUser else { throw AuthFailure.unknown }
        return (url.host() == AppConfig.resetPasswordURL.host() ? .passwordRecovery : .signedIn, user)
    }

    func updatePassword(_ password: String) async throws {}

    func signOut() async { currentUser = nil }

    func fetchProfile(userID: UUID) async throws -> Profile {
        guard let profile = profiles[userID] else { throw AuthFailure.unknown }
        return profile
    }

    func completeOnboarding(userID: UUID, householdID: UUID, categories: [CategoryDraft]) async throws {
        savedCategories = CategoryRow.onboardingRows(chosen: categories, householdID: householdID)
        self.categories = savedCategories.map {
            CategoryItem(id: $0.id, householdID: $0.householdID, name: $0.name, emoji: $0.emoji,
                                color: $0.color, kind: $0.kind, sortOrder: $0.sortOrder)
        }
        profiles[userID]?.onboardingCompleted = true
    }

    // MARK: DataRepository

    func fetchCategories(householdID: UUID) async throws -> [CategoryItem] {
        if categories.isEmpty { seed(householdID: householdID) }
        return categories.filter { $0.householdID == householdID }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func fetchMembers(householdID: UUID) async throws -> [HouseholdMember] {
        profiles.values.filter { $0.activeHouseholdID == householdID }.map { HouseholdMember(id: $0.id, fullName: $0.fullName) }
    }

    func fetchTransactions(householdID: UUID, since: Date) async throws -> [TransactionRow] {
        TransactionSummary.sortedNewestFirst(transactions.values.filter { $0.householdID == householdID && $0.occurredAt >= since })
    }

    func fetchTransactions(householdID: UUID, before: Date, limit: Int) async throws -> [TransactionRow] {
        Array(TransactionSummary.sortedNewestFirst(transactions.values.filter { $0.householdID == householdID && $0.occurredAt < before }).prefix(limit))
    }

    func saveTransactions(_ rows: [TransactionRow]) async throws {
        for row in rows { transactions[row.id] = row }
    }

    func insertIgnoringDuplicates(_ rows: [TransactionRow]) async throws {
        for row in rows where !transactions.values.contains(where: {
            $0.householdID == row.householdID && $0.source == row.source && $0.externalID != nil && $0.externalID == row.externalID
        }) {
            transactions[row.id] = row
        }
    }

    func deleteTransaction(id: UUID) async throws {
        transactions[id] = nil
    }

    func saveCategory(_ category: CategoryItem) async throws {
        categories.removeAll { $0.id == category.id }
        categories.append(category)
    }

    func fetchRecurringRules(userID: UUID) async throws -> [RecurringRuleRow] {
        rules.values.filter { $0.userID == userID && $0.isActive }
    }

    func saveRecurringRule(_ rule: RecurringRuleRow) async throws {
        rules[rule.id] = rule
    }

    func fetchExchangeRates() async throws -> ExchangeRates {
        ExchangeRates(
            base: .ils,
            rates: [.usd: Decimal(string: "3.70")!, .eur: Decimal(string: "4.00")!, .gbp: Decimal(string: "4.70")!,
                    "RUB": Decimal(string: "0.045")!, "THB": Decimal(string: "0.11")!],
            date: .now
        )
    }

    func fetchMerchantMap(householdID: UUID) async throws -> [MerchantCategoryRow] {
        merchantMap.filter { $0.householdID == householdID }
    }

    func recordMerchantCategory(householdID: UUID, merchant: String, categoryID: UUID) async throws {
        let key = CategorySuggester.normalize(merchant)
        guard !key.isEmpty else { return }
        if let index = merchantMap.firstIndex(where: { $0.householdID == householdID && $0.merchantKey == key && $0.categoryID == categoryID }) {
            merchantMap[index].timesUsed += 1
        } else {
            merchantMap.append(MerchantCategoryRow(householdID: householdID, merchantKey: key, categoryID: categoryID, timesUsed: 1))
        }
    }

    func updateQuickLogEnabled(userID: UUID, enabled: Bool) async throws {
        profiles[userID]?.quickLogEnabled = enabled
    }

    /// Returning test users (who skip onboarding) get the default categories and a few
    /// transactions so screens aren't empty in screenshots.
    private func seed(householdID: UUID) {
        let drafts = CategoryRow.onboardingRows(chosen: DefaultCategories.expenses, householdID: householdID)
        categories = drafts.map {
            CategoryItem(id: $0.id, householdID: $0.householdID, name: $0.name, emoji: $0.emoji,
                                color: $0.color, kind: $0.kind, sortOrder: $0.sortOrder)
        }
        guard let user = currentUser, transactions.isEmpty,
              profiles[user]?.onboardingCompleted == true, savedCategories.isEmpty else { return }
        let now = Date.now
        let samples: [(Int, Decimal, String, String, Int)] = [
            (0, Decimal(string: "18.5")!, "ארומה", "ILS", 15),
            (1, Decimal(string: "312.4")!, "שופרסל דיל", "ILS", 1),
            (2, Decimal(string: "120")!, "פז", "ILS", 3),
            (3, Decimal(string: "64.9")!, "Amazon", "USD", 2),
            (4, Decimal(string: "45")!, "סינמה סיטי", "ILS", 9),
        ]
        for (index, amount, merchant, currency, category) in samples {
            let date = Calendar.current.date(byAdding: .hour, value: -(index * 20 + 2), to: now)!
            let rate: Decimal = currency == "USD" ? Decimal(string: "3.7")! : 1
            let converted = (amount * rate).rounded(scale: 2)
            let row = TransactionRow(
                householdID: householdID, userID: user, categoryID: categories[category].id, kind: .expense,
                originalAmount: amount, originalCurrency: currency, exchangeRate: rate,
                amount: converted, currency: "ILS", merchant: merchant, occurredAt: date,
                source: index == 0 ? .applePay : .manual
            )
            transactions[row.id] = row
        }
        let salary = TransactionRow(
            householdID: householdID, userID: user, categoryID: nil, kind: .income,
            originalAmount: 12_500, originalCurrency: "ILS", amount: 12_500, currency: "ILS",
            merchant: "משכורת", occurredAt: Calendar.current.date(byAdding: .day, value: -3, to: now)!, source: .recurring
        )
        transactions[salary.id] = salary
    }
}
