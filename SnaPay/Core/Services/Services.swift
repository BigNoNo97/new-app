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
