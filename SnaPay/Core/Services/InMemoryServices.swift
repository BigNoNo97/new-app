import Foundation
import SnaPayCore

/// In-memory auth and data for UI tests and previews. Any email/password pair signs up;
/// "wrong@example.com" fails to log in so tests can exercise error states.
///
/// Shared accounts: "shared@example.com" logs in to a household shared with מיכל, and
/// "invited@example.com" logs in with a pending invite from her.
final class InMemoryServices: AuthServicing, AccountRepository, DataRepository {
    private var profiles: [UUID: Profile] = [:]
    private var categories: [CategoryItem] = []
    private var transactions: [UUID: TransactionRow] = [:]
    private var rules: [UUID: RecurringRuleRow] = [:]
    private var merchantMap: [MerchantCategoryRow] = []
    private var passwords: [String: (UUID, String)] = [:]
    private(set) var savedCategories: [CategoryRow] = []
    private var currentUser: UUID?
    private var emails: [UUID: String] = [:]
    private var households: [UUID: HouseholdRow] = [:]
    private var owners: [UUID: UUID] = [:]
    private var invites: [(row: HouseholdInviteRow, inviter: UUID)] = []
    private var deviceTokens: [String: UUID] = [:]

    static let partnerName = "מיכל כהן"

    func restoreSession() async -> UUID? { currentUser }

    func signUp(fullName: String, email: String, password: String, mainCurrency: String) async throws -> SignUpOutcome {
        let key = CredentialsValidator.normalizedEmail(email)
        guard passwords[key] == nil else { throw AuthFailure.emailAlreadyRegistered }
        let id = UUID()
        passwords[key] = (id, password)
        emails[id] = key
        profiles[id] = Profile(id: id, fullName: fullName, mainCurrency: mainCurrency, activeHouseholdID: makeHousehold(owner: id), createdAt: .now)
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
        emails[id] = key
        profiles[id] = Profile(id: id, fullName: "משתמש בדיקה", onboardingCompleted: true, activeHouseholdID: makeHousehold(owner: id), createdAt: .now)
        currentUser = id
        if key == "shared@example.com" || key == "invited@example.com" {
            seedPartner(for: id, joined: key == "shared@example.com")
        }
        return id
    }

    func sendPasswordReset(email: String) async throws {}

    func handleRedirect(_ url: URL) async throws -> (AuthRedirect, UUID) {
        guard let user = currentUser else { throw AuthFailure.unknown }
        return (url.host() == AppConfig.resetPasswordURL.host() ? .passwordRecovery : .signedIn, user)
    }

    func updatePassword(_ password: String) async throws {}

    func signOut() async { currentUser = nil }

    var currentEmail: String? { currentUser.flatMap { emails[$0] } }

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
        if !categories.contains(where: { $0.householdID == householdID }) { seed(householdID: householdID) }
        return categories.filter { $0.householdID == householdID }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func fetchMembers(householdID: UUID) async throws -> [HouseholdMember] {
        profiles.values
            .filter { $0.activeHouseholdID == householdID }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            .map { HouseholdMember(id: $0.id, fullName: $0.fullName, isOwner: owners[householdID] == $0.id) }
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

    func updateProfile(userID: UUID, changes: ProfileChanges) async throws {
        profiles[userID]?.apply(changes)
    }

    // MARK: Shared households

    func fetchHousehold(id: UUID) async throws -> HouseholdRow {
        households[id] ?? HouseholdRow(id: id, name: "", isShared: false)
    }

    func setHouseholdShared(id: UUID, isShared: Bool) async throws {
        households[id, default: HouseholdRow(id: id, name: "", isShared: false)].isShared = isShared
    }

    func fetchSentInvites(householdID: UUID) async throws -> [HouseholdInviteRow] {
        invites.map(\.row).filter { $0.householdID == householdID && $0.status == .pending }
    }

    func sendInvite(householdID: UUID, email: String) async throws {
        let key = CredentialsValidator.normalizedEmail(email)
        guard !invites.contains(where: { $0.row.householdID == householdID && $0.row.email == key && $0.row.status == .pending }) else {
            throw HouseholdFailure.inviteAlreadyPending
        }
        invites.append((HouseholdInviteRow(householdID: householdID, email: key, createdAt: .now), currentUser ?? UUID()))
    }

    func revokeInvite(_ id: UUID) async throws {
        if let index = invites.firstIndex(where: { $0.row.id == id }) { invites[index].row.status = .revoked }
    }

    func removeMember(_ userID: UUID) async throws {
        guard let me = currentUser, let household = profiles[me]?.activeHouseholdID, owners[household] == me else {
            throw HouseholdFailure.notOwner
        }
        split(userID, from: household)
    }

    func notifyPartners(transactionID: UUID) async throws {}

    func fetchPendingInvites() async throws -> [PendingInvite] {
        guard let me = currentUser, let email = emails[me] else { return [] }
        return invites.filter { $0.row.email == email && $0.row.status == .pending }.map {
            PendingInvite(id: $0.row.id, householdID: $0.row.householdID,
                          inviterName: profiles[$0.inviter]?.fullName ?? "", createdAt: $0.row.createdAt ?? .now)
        }
    }

    func acceptInvite(_ id: UUID) async throws -> UUID {
        guard let me = currentUser, let index = invites.firstIndex(where: { $0.row.id == id && $0.row.status == .pending }) else {
            throw HouseholdFailure.inviteNotFound
        }
        let target = invites[index].row.householdID
        invites[index].row.status = .accepted
        if let previous = profiles[me]?.activeHouseholdID {
            for (key, row) in transactions where row.userID == me && row.householdID == previous {
                transactions[key]?.householdID = target
                transactions[key]?.categoryID = mappedCategory(row.categoryID, to: target)
            }
        }
        profiles[me]?.activeHouseholdID = target
        households[target]?.isShared = true
        return target
    }

    func declineInvite(_ id: UUID) async throws {
        guard let index = invites.firstIndex(where: { $0.row.id == id }) else { throw HouseholdFailure.inviteNotFound }
        invites[index].row.status = .declined
    }

    func leaveHousehold() async throws -> UUID {
        guard let me = currentUser, let household = profiles[me]?.activeHouseholdID else { throw HouseholdFailure.unknown }
        return split(me, from: household)
    }

    func registerDeviceToken(_ token: String, environment: String) async throws {
        deviceTokens[token] = currentUser
    }

    func unregisterDeviceToken(_ token: String) async throws {
        deviceTokens[token] = nil
    }

    func deleteAccount(password: String) async throws {
        guard let me = currentUser else { return }
        profiles[me] = nil
        transactions = transactions.filter { $0.value.userID != me }
        passwords = passwords.filter { $0.value.0 != me }
        currentUser = nil
    }

    // MARK: Household helpers

    private func makeHousehold(owner: UUID) -> UUID {
        let id = UUID()
        households[id] = HouseholdRow(id: id, name: "", isShared: false)
        owners[id] = owner
        return id
    }

    /// The category in `household` with the same name, copying it if needed.
    private func mappedCategory(_ id: UUID?, to household: UUID) -> UUID? {
        guard let id, let source = categories.first(where: { $0.id == id }) else { return nil }
        if let match = categories.first(where: { $0.householdID == household && $0.name == source.name && $0.kind == source.kind }) {
            return match.id
        }
        var copy = source
        copy.id = UUID()
        copy.householdID = household
        categories.append(copy)
        return copy.id
    }

    @discardableResult
    private func split(_ user: UUID, from household: UUID) -> UUID {
        let personal = makeHousehold(owner: user)
        for category in categories where category.householdID == household {
            _ = mappedCategory(category.id, to: personal)
        }
        for (key, row) in transactions where row.userID == user && row.householdID == household {
            transactions[key]?.householdID = personal
            transactions[key]?.categoryID = mappedCategory(row.categoryID, to: personal)
        }
        profiles[user]?.activeHouseholdID = personal
        let remaining = profiles.values.filter { $0.activeHouseholdID == household }
        households[household]?.isShared = remaining.count > 1
        if owners[household] == user, let next = remaining.first { owners[household] = next.id }
        return personal
    }

    /// מיכל with her own household and a couple of expenses. When `joined`, the test user is
    /// already a member of it; otherwise מיכל has invited them.
    private func seedPartner(for user: UUID, joined: Bool) {
        let partner = UUID()
        let household = makeHousehold(owner: partner)
        emails[partner] = "michal@example.com"
        profiles[partner] = Profile(id: partner, fullName: Self.partnerName, onboardingCompleted: true,
                                    activeHouseholdID: household, createdAt: .distantPast)
        let drafts = CategoryRow.onboardingRows(chosen: DefaultCategories.expenses, householdID: household)
        categories += drafts.map {
            CategoryItem(id: $0.id, householdID: $0.householdID, name: $0.name, emoji: $0.emoji,
                         color: $0.color, kind: $0.kind, sortOrder: $0.sortOrder)
        }
        let groceries = categories.first { $0.householdID == household && $0.name == "סופר" }?.id
        for (index, merchant) in ["רמי לוי", "סופר-פארם"].enumerated() {
            let amount: Decimal = index == 0 ? Decimal(string: "212.4")! : Decimal(string: "89.9")!
            let row = TransactionRow(
                householdID: household, userID: partner, categoryID: groceries, kind: .expense,
                originalAmount: amount, originalCurrency: "ILS", amount: amount, currency: "ILS",
                merchant: merchant, occurredAt: Date.now.addingTimeInterval(-Double(index + 1) * 5_400), source: .applePay
            )
            transactions[row.id] = row
        }
        if joined {
            profiles[user]?.activeHouseholdID = household
            households[household]?.isShared = true
            seedSamples(householdID: household, user: user)
        } else {
            invites.append((HouseholdInviteRow(householdID: household, email: emails[user] ?? "", createdAt: .now), partner))
        }
    }

    /// Returning test users (who skip onboarding) get the default categories and a few
    /// transactions so screens aren't empty in screenshots.
    private func seed(householdID: UUID) {
        let drafts = CategoryRow.onboardingRows(chosen: DefaultCategories.expenses, householdID: householdID)
        let seeded = drafts.map {
            CategoryItem(id: $0.id, householdID: $0.householdID, name: $0.name, emoji: $0.emoji,
                                color: $0.color, kind: $0.kind, sortOrder: $0.sortOrder)
        }
        categories += seeded
        guard let user = currentUser, !transactions.values.contains(where: { $0.userID == user }),
              profiles[user]?.onboardingCompleted == true, savedCategories.isEmpty else { return }
        seedSamples(householdID: householdID, user: user)
    }

    /// A few expenses and a salary for `user`, in `householdID`'s categories.
    private func seedSamples(householdID: UUID, user: UUID) {
        let seeded = categories.filter { $0.householdID == householdID && $0.kind == .expense }.sorted { $0.sortOrder < $1.sortOrder }
        guard seeded.count > 15 else { return }
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
                householdID: householdID, userID: user, categoryID: seeded[category].id, kind: .expense,
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
