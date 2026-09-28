import Foundation
import Observation
import SnaPayCore

enum AppRoute: Equatable {
    case launching
    case serverNotConfigured
    case notificationPrompt
    /// Welcome, sign-up and log-in (one navigation stack).
    case welcome
    case checkEmail(String)
    case resetPassword
    case niceToMeetYou
    case categories
    case locked
    case main
    /// The profile couldn't be loaded because the server is unreachable.
    case connectionProblem
}

/// Decides which screen the app shows and runs the account flows.
@Observable
final class AppState {
    private(set) var route: AppRoute = .launching
    private(set) var profile: Profile?
    /// Set when a link from an email couldn't be completed (expired, already used).
    var linkError: AuthFailure?

    private let auth: AuthServicing
    private let account: AccountRepository
    private let data: DataRepository
    /// The signed-in user's data; set once they reach the main app.
    private(set) var store: TransactionStore?
    private var userID: UUID?
    private var isUnlocked = false

    init(auth: AuthServicing, account: AccountRepository, data: DataRepository) {
        self.auth = auth
        self.account = account
        self.data = data
    }

    /// The services the app runs with: Supabase, or in-memory for UI tests.
    static func live() -> AppState {
        if AppConfig.isUITesting {
            prepareQuickLogForUITests()
            let services = InMemoryServices()
            return AppState(auth: services, account: services, data: services)
        }
        guard let services = SupabaseServices.shared else {
            let services = InMemoryServices()
            let state = AppState(auth: services, account: services, data: services)
            state.route = .serverNotConfigured
            return state
        }
        return AppState(auth: services, account: services, data: services)
    }

    /// Every UI test starts from a clean quick-log state (the shared files outlive the app).
    private static func prepareQuickLogForUITests() {
        QuickLogStorage.erase()
        DevicePreferences.hidesQuickLogSetupCard = false
        guard AppConfig.seedsQuickLogCapture else { return }
        QuickLogStorage.updateInbox {
            $0.add(CapturedPayment(
                amount: Decimal(string: "23.9")!, currency: "ILS", merchant: "קפה לנדוור",
                card: "Visa", capturedAt: .now.addingTimeInterval(-600)
            ))
        }
    }

    // MARK: Launch

    func start() async {
        guard route == .launching else { return }
        if !AppConfig.isUITesting && !DevicePreferences.hasSeenNotificationPrompt {
            route = .notificationPrompt
            return
        }
        await routeFromSession()
    }

    func finishNotificationPrompt(allow: Bool) async {
        DevicePreferences.hasSeenNotificationPrompt = true
        if allow {
            await NotificationPermission.request()
        }
        await routeFromSession()
    }

    private func routeFromSession() async {
        if let user = await auth.restoreSession() {
            await enterApp(userID: user)
        } else {
            route = .welcome
        }
    }

    // MARK: Account flows

    func signUp(fullName: String, email: String, password: String, mainCurrency: String) async throws {
        switch try await auth.signUp(fullName: fullName, email: email, password: password, mainCurrency: mainCurrency) {
        case .signedIn:
            if let user = await auth.restoreSession() {
                await enterApp(userID: user)
            }
        case .needsEmailConfirmation:
            route = .checkEmail(CredentialsValidator.normalizedEmail(email))
        }
    }

    func logIn(email: String, password: String) async throws {
        let user = try await auth.logIn(email: email, password: password)
        isUnlocked = true
        await enterApp(userID: user)
    }

    func sendPasswordReset(email: String) async throws {
        try await auth.sendPasswordReset(email: email)
    }

    func updatePassword(_ password: String) async throws {
        try await auth.updatePassword(password)
        if let userID {
            await enterApp(userID: userID)
        }
    }

    func handle(url: URL) async {
        do {
            let (kind, user) = try await auth.handleRedirect(url)
            userID = user
            isUnlocked = true
            if kind == .passwordRecovery {
                route = .resetPassword
            } else {
                await enterApp(userID: user)
            }
        } catch {
            linkError = error as? AuthFailure ?? .unknown
        }
    }

    func backToWelcome() {
        route = .welcome
    }

    func signOut() async {
        await auth.signOut()
        store?.eraseLocalData()
        store = nil
        DevicePreferences.cachedProfile = nil
        profile = nil
        userID = nil
        isUnlocked = false
        route = .welcome
    }

    // MARK: Onboarding

    func continueFromNiceToMeetYou() {
        route = .categories
    }

    func completeOnboarding(categories: [CategoryDraft]) async throws {
        guard let userID, let profile, let household = profile.activeHouseholdID else {
            throw AuthFailure.unknown
        }
        try await account.completeOnboarding(userID: userID, householdID: household, categories: categories)
        self.profile?.onboardingCompleted = true
        openStore()
        route = .main
    }

    // MARK: Face ID

    func setFaceIDEnabled(_ enabled: Bool) {
        DevicePreferences.isFaceIDEnabled = enabled
    }

    func unlock() async {
        if await BiometricService.authenticate(reason: "פתיחת SnaPay") {
            isUnlocked = true
            if route == .locked { route = .main }
        }
    }

    /// Called when the app goes to the background: lock it again if Face ID is on.
    func appDidEnterBackground() {
        guard DevicePreferences.isFaceIDEnabled, route == .main else { return }
        isUnlocked = false
        route = .locked
    }

    // MARK: Helpers

    private func enterApp(userID: UUID) async {
        self.userID = userID
        let profile: Profile
        do {
            profile = try await account.fetchProfile(userID: userID)
            DevicePreferences.cachedProfile = profile
        } catch let error where Self.isConnectionError(error) {
            // Offline: carry on with the profile saved on this device, if it's this user's.
            guard let cached = DevicePreferences.cachedProfile, cached.id == userID else {
                route = .connectionProblem
                return
            }
            profile = cached
        } catch {
            // Session exists but the profile can't be read (e.g. deleted account): start over.
            await auth.signOut()
            route = .welcome
            return
        }
        self.profile = profile
        if !profile.onboardingCompleted {
            route = .niceToMeetYou
            return
        }
        openStore()
        if DevicePreferences.isFaceIDEnabled && !isUnlocked && !AppConfig.isUITesting {
            route = .locked
        } else {
            route = .main
        }
    }

    private func openStore() {
        guard let profile, let userID, let household = profile.activeHouseholdID else { return }
        guard store?.userID != userID else { return }
        let store = TransactionStore(profile: profile, userID: userID, householdID: household, repository: data)
        self.store = store
        Task { await store.start() }
    }

    func retryAfterConnectionProblem() async {
        guard let userID else {
            route = .welcome
            return
        }
        await enterApp(userID: userID)
    }

    private static func isConnectionError(_ error: Error) -> Bool {
        error is URLError || (error as? AuthFailure) == .network
    }
}
