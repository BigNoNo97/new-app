import Foundation
import Supabase
import SnaPayCore

/// Auth and account data backed by Supabase.
final class SupabaseServices: AuthServicing, AccountRepository {
    let client: SupabaseClient

    init(url: URL, anonKey: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    // MARK: AuthServicing

    func restoreSession() async -> UUID? {
        if let session = try? await client.auth.session {
            return session.user.id
        }
        // Offline with an expired access token: keep the user signed in; the SDK refreshes the
        // session on the next request once the connection is back.
        return client.auth.currentSession?.user.id
    }

    func signUp(fullName: String, email: String, password: String, mainCurrency: String) async throws -> SignUpOutcome {
        do {
            let response = try await client.auth.signUp(
                email: CredentialsValidator.normalizedEmail(email),
                password: password,
                data: [
                    "full_name": .string(fullName.trimmingCharacters(in: .whitespacesAndNewlines)),
                    "main_currency": .string(mainCurrency),
                ],
                redirectTo: AppConfig.authCallbackURL
            )
            return response.session == nil ? .needsEmailConfirmation : .signedIn
        } catch {
            throw Self.map(error)
        }
    }

    func logIn(email: String, password: String) async throws -> UUID {
        do {
            let session = try await client.auth.signIn(
                email: CredentialsValidator.normalizedEmail(email),
                password: password
            )
            return session.user.id
        } catch {
            throw Self.map(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            try await client.auth.resetPasswordForEmail(
                CredentialsValidator.normalizedEmail(email),
                redirectTo: AppConfig.resetPasswordURL
            )
        } catch {
            throw Self.map(error)
        }
    }

    func handleRedirect(_ url: URL) async throws -> (AuthRedirect, UUID) {
        do {
            let session = try await client.auth.session(from: url)
            let kind: AuthRedirect = url.host() == AppConfig.resetPasswordURL.host() ? .passwordRecovery : .signedIn
            return (kind, session.user.id)
        } catch {
            throw Self.map(error)
        }
    }

    func updatePassword(_ password: String) async throws {
        do {
            try await client.auth.update(user: UserAttributes(password: password))
        } catch {
            throw Self.map(error)
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    // MARK: AccountRepository

    func fetchProfile(userID: UUID) async throws -> Profile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: userID.uuidString)
            .single()
            .execute()
            .value
    }

    func completeOnboarding(userID: UUID, householdID: UUID, categories: [CategoryDraft]) async throws {
        let rows = CategoryRow.onboardingRows(chosen: categories, householdID: householdID)
        try await client.from("categories").upsert(rows).execute()
        try await client
            .from("profiles")
            .update(["onboarding_completed": true])
            .eq("id", value: userID.uuidString)
            .execute()
    }

    // MARK: Errors

    /// Maps Supabase errors to cases the UI explains. Matches on the server's messages,
    /// which are stable across SDK versions.
    static func map(_ error: Error) -> AuthFailure {
        if let failure = error as? AuthFailure { return failure }
        if error is URLError { return .network }
        let message = String(describing: error).lowercased()
        if message.contains("invalid login credentials") || message.contains("invalid_credentials") {
            return .invalidCredentials
        }
        if message.contains("email not confirmed") || message.contains("email_not_confirmed") {
            return .emailNotConfirmed
        }
        if message.contains("already registered") || message.contains("user_already_exists") {
            return .emailAlreadyRegistered
        }
        if message.contains("weak_password") || message.contains("password should") {
            return .weakPassword
        }
        if message.contains("rate limit") || message.contains("over_email_send_rate_limit") {
            return .rateLimited
        }
        return .unknown
    }
}
