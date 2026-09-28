import UIKit
import UserNotifications

extension Notification.Name {
    /// A push arrived while the app was open, or the user tapped one: refresh the data.
    static let remoteActivity = Notification.Name("remoteActivity")
}

/// Remote notifications: registering with APNs, the device token, and presentation.
///
/// The token goes to the server (`device_tokens`) once someone is signed in; the
/// notify-partners function uses it to tell this device about a partner's new expense.
final class PushNotifications: NSObject {
    static let shared = PushNotifications()

    private(set) var deviceToken: String?
    /// Called when APNs hands over a (new) token.
    var onToken: ((String) -> Void)?

    /// APNs environment the token belongs to: debug builds talk to the sandbox.
    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Asks APNs for a token if the user allowed notifications. Safe to call on every launch.
    func registerIfAllowed() async {
        guard !AppConfig.isUITesting, await Self.isAllowed() else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Whether the user allowed notifications (read off the main actor: the settings object
    /// isn't Sendable).
    nonisolated static func isAllowed() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }

    func didRegister(tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        guard token != deviceToken else { return }
        deviceToken = token
        onToken?(token)
    }
}

extension PushNotifications: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { NotificationCenter.default.post(name: .remoteActivity, object: nil) }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { NotificationCenter.default.post(name: .remoteActivity, object: nil) }
    }
}

/// Hooks UIKit's push callbacks into SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushNotifications.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotifications.shared.didRegister(tokenData: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulators and unsigned builds can't register; partner notifications just don't arrive.
    }
}
