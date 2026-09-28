import Foundation
import SnaPayCore

enum SignUpOutcome: Equatable {
    case signedIn
    /// The server sent a confirmation email; the user signs in from its link.
    case needsEmailConfirmation
}

enum AuthRedirect: Equatable {
    case signedIn
    case passwordRecovery
}

/// A failure the UI can explain in Hebrew.
enum AuthFailure: Error, Equatable {
    case invalidCredentials
    case emailNotConfirmed
    case emailAlreadyRegistered
    case weakPassword
    case rateLimited
    case network
    case unknown
}

/// A failure in the shared-account flows the UI can explain in Hebrew.
enum HouseholdFailure: Error, Equatable {
    case inviteAlreadyPending
    case inviteNotFound
    case alreadyMember
    case notOwner
    case network
    case unknown
}

protocol AuthServicing: AnyObject {
    /// The signed-in user, restoring (and refreshing) a saved session if there is one.
    func restoreSession() async -> UUID?
    func signUp(fullName: String, email: String, password: String, mainCurrency: String) async throws -> SignUpOutcome
    func logIn(email: String, password: String) async throws -> UUID
    func sendPasswordReset(email: String) async throws
    /// Completes an email link (confirmation or password recovery) opened in the app.
    func handleRedirect(_ url: URL) async throws -> (AuthRedirect, UUID)
    func updatePassword(_ password: String) async throws
    func signOut() async
    /// The signed-in user's email, for the settings screen.
    var currentEmail: String? { get }
}

protocol AccountRepository: AnyObject {
    func fetchProfile(userID: UUID) async throws -> Profile
    /// Saves the onboarding categories (idempotent) and marks onboarding as done.
    func completeOnboarding(userID: UUID, householdID: UUID, categories: [CategoryDraft]) async throws

    // Shared households
    /// Invites addressed to my email that I haven't answered.
    func fetchPendingInvites() async throws -> [PendingInvite]
    /// Joins the invite's household (my own entries move with me). Returns its id.
    func acceptInvite(_ id: UUID) async throws -> UUID
    func declineInvite(_ id: UUID) async throws
    /// Leaves the shared household for a new personal one (my entries move with me).
    func leaveHousehold() async throws -> UUID

    // Push notifications and account
    func registerDeviceToken(_ token: String, environment: String) async throws
    func unregisterDeviceToken(_ token: String) async throws
    /// Permanently deletes the account and everything the user entered.
    func deleteAccount() async throws
}

/// Household data: categories, members, transactions, recurring rules, exchange rates and the
/// quick-log merchant map.
protocol DataRepository: AnyObject {
    func fetchCategories(householdID: UUID) async throws -> [CategoryItem]
    func fetchMembers(householdID: UUID) async throws -> [HouseholdMember]
    /// Transactions that occurred at or after `since`, newest first.
    func fetchTransactions(householdID: UUID, since: Date) async throws -> [TransactionRow]
    /// Up to `limit` transactions that occurred before `before`, newest first.
    func fetchTransactions(householdID: UUID, before: Date, limit: Int) async throws -> [TransactionRow]
    /// Inserts or updates by id.
    func saveTransactions(_ rows: [TransactionRow]) async throws
    /// Inserts generated transactions, skipping any whose (household, source, external id) exists.
    func insertIgnoringDuplicates(_ rows: [TransactionRow]) async throws
    func deleteTransaction(id: UUID) async throws
    func saveCategory(_ category: CategoryItem) async throws
    func fetchRecurringRules(userID: UUID) async throws -> [RecurringRuleRow]
    func saveRecurringRule(_ rule: RecurringRuleRow) async throws
    func fetchExchangeRates() async throws -> ExchangeRates
    /// How often the household filed each merchant under each category (quick-log suggestions).
    func fetchMerchantMap(householdID: UUID) async throws -> [MerchantCategoryRow]
    /// Counts one more choice of `categoryID` for `merchant`.
    func recordMerchantCategory(householdID: UUID, merchant: String, categoryID: UUID) async throws
    func updateProfile(userID: UUID, changes: ProfileChanges) async throws

    // Shared households
    func fetchHousehold(id: UUID) async throws -> HouseholdRow
    func setHouseholdShared(id: UUID, isShared: Bool) async throws
    /// Pending invites my household sent.
    func fetchSentInvites(householdID: UUID) async throws -> [HouseholdInviteRow]
    func sendInvite(householdID: UUID, email: String) async throws
    func revokeInvite(_ id: UUID) async throws
    /// Owner only: the member moves to a personal household with their entries.
    func removeMember(_ userID: UUID) async throws
    /// Pushes a notification about a new transaction to the other members (once per row).
    func notifyPartners(transactionID: UUID) async throws
}
