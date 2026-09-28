import SwiftUI

@main
struct SnaPayApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // The app is Hebrew-only for now, so force RTL even when the phone is set to
                // another language. Once English and Russian land, this follows the locale.
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
        }
    }
}
