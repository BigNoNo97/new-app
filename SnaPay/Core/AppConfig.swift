import Foundation

/// Build-time configuration and launch flags.
enum AppConfig {
    /// Values injected into Info.plist from Config/Secrets.xcconfig (written by CI from
    /// repository variables). Empty until the Supabase project exists.
    static let supabaseURL: URL? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              value.hasPrefix("https://") else { return nil }
        return URL(string: value)
    }()

    static let supabaseAnonKey: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }()

    static var isServerConfigured: Bool { supabaseURL != nil && supabaseAnonKey != nil }

    /// UI tests run the app against in-memory services.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    static let forcesDarkMode = ProcessInfo.processInfo.arguments.contains("-uiTestingDark")

    /// Shared with the widget and the quick-log intent.
    static let appGroup = "group.com.bignono97.snapay"

    static let authCallbackURL = URL(string: "snapay://auth-callback")!
    static let resetPasswordURL = URL(string: "snapay://reset-password")!

    // Published with the launch stage (GitHub Pages).
    static let termsURL = URL(string: "https://bignono97.github.io/new-app/terms")!
    static let privacyURL = URL(string: "https://bignono97.github.io/new-app/privacy")!
}
