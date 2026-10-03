import Foundation

/// Build-time configuration and launch flags.
enum AppConfig {
    /// Firebase settings, injected into Info.plist from Config/Secrets.xcconfig (written by CI
    /// from repository variables). Nil until the Firebase project exists.
    nonisolated static let firebase: FirebaseSettings? = {
        func value(_ key: String) -> String? {
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
                  !value.isEmpty, !value.hasPrefix("$(") else { return nil }
            return value
        }
        guard let apiKey = value("FIREBASE_API_KEY"), let projectID = value("FIREBASE_PROJECT_ID"),
              let appID = value("FIREBASE_APP_ID"), let senderID = value("FIREBASE_SENDER_ID") else { return nil }
        return FirebaseSettings(apiKey: apiKey, projectID: projectID, appID: appID, senderID: senderID)
    }()

    static var isServerConfigured: Bool { firebase != nil }

    /// UI tests run the app against in-memory services.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    static let forcesDarkMode = ProcessInfo.processInfo.arguments.contains("-uiTestingDark")
    /// UI tests: start with an Apple Pay payment waiting for a category.
    static let seedsQuickLogCapture = ProcessInfo.processInfo.arguments.contains("-uiTestingQuickLog")

    /// Shared with the widget and the quick-log intent.
    static let appGroup = "group.com.bignono97.snapay"

    /// The ready-made "תיעוד ב-SnaPay" shortcut (an iCloud link: one tap and "Add Shortcut"). It
    /// passes the Wallet transaction's amount, merchant and card to `LogPaymentIntent`, so the
    /// automation only has to run it. iOS can't install the automation itself. Nil hides the button
    /// and the guide falls back to adding the action by hand.
    static let quickLogShortcutURL: URL? = nil

    static let authCallbackURL = URL(string: "snapay://auth-callback")!
    static let resetPasswordURL = URL(string: "snapay://reset-password")!

    // Published with the launch stage (GitHub Pages).
    static let termsURL = URL(string: "https://bignono97.github.io/new-app/terms")!
    static let privacyURL = URL(string: "https://bignono97.github.io/new-app/privacy")!
}

/// The values from the Firebase console's GoogleService-Info.plist that the app needs.
nonisolated struct FirebaseSettings: Sendable {
    let apiKey: String
    let projectID: String
    let appID: String
    let senderID: String
}
