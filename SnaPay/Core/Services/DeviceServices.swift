import Foundation
import SnaPayCore
import LocalAuthentication
import UserNotifications

/// Face ID / Touch ID.
enum BiometricService {
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var isFaceID: Bool {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .faceID
    }

    /// Asks for Face ID, falling back to the device passcode.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "ביטול"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

enum NotificationPermission {
    @discardableResult
    static func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }
}

/// Small per-device preferences.
enum DevicePreferences {
    private static let defaults = UserDefaults.standard

    static var hasSeenNotificationPrompt: Bool {
        get { defaults.bool(forKey: "hasSeenNotificationPrompt") }
        set { defaults.set(newValue, forKey: "hasSeenNotificationPrompt") }
    }

    /// The last profile loaded from the server, so the app opens offline.
    static var cachedProfile: Profile? {
        get { defaults.data(forKey: "cachedProfile").flatMap { try? JSONDecoder().decode(Profile.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "cachedProfile") }
    }

    /// The user closed the home screen's "set up quick-log" card.
    static var hidesQuickLogSetupCard: Bool {
        get { defaults.bool(forKey: "hidesQuickLogSetupCard") }
        set { defaults.set(newValue, forKey: "hidesQuickLogSetupCard") }
    }

    static var isFaceIDEnabled: Bool {
        get { defaults.bool(forKey: "isFaceIDEnabled") }
        set { defaults.set(newValue, forKey: "isFaceIDEnabled") }
    }
}
