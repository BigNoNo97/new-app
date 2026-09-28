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
}

protocol AccountRepository: AnyObject {
    func fetchProfile(userID: UUID) async throws -> Profile
    /// Saves the onboarding categories (idempotent) and marks onboarding as done.
    func completeOnboarding(userID: UUID, householdID: UUID, categories: [CategoryDraft]) async throws
}

/// Household data: categories, members, transactions, recurring rules and exchange rates.
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
}
