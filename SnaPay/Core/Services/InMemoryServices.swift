import Foundation
import SnaPayCore

/// In-memory auth and data for UI tests and previews. Any email/password pair signs up;
/// "wrong@example.com" fails to log in so tests can exercise error states.
final class InMemoryServices: AuthServicing, AccountRepository {
    private var profiles: [UUID: Profile] = [:]
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
        profiles[userID]?.onboardingCompleted = true
    }
}
