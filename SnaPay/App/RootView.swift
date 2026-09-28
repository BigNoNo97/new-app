import SwiftUI

/// Shows the screen for the current `AppRoute`.
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppBackground()
            content
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: app.route)
        .task { await app.start() }
        .onOpenURL { url in
            Task { await app.handle(url: url) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.appDidEnterBackground() }
        }
        .alert(
            "הקישור לא עבד",
            isPresented: Binding(get: { app.linkError != nil }, set: { if !$0 { app.linkError = nil } })
        ) {
            Button("הבנתי", role: .cancel) {}
        } message: {
            Text("ייתכן שהקישור כבר שומש או שפג תוקפו. אפשר לבקש קישור חדש ממסך ההתחברות.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.route {
        case .launching: LaunchView()
        case .serverNotConfigured: ServerNotConfiguredView()
        case .notificationPrompt: NotificationPermissionView()
        case .welcome: WelcomeFlowView()
        case .checkEmail(let email): CheckEmailView(email: email)
        case .resetPassword: ResetPasswordView()
        case .niceToMeetYou: NiceToMeetYouView()
        case .categories: CategoryPickerView()
        case .locked: FaceIDLockView()
        case .main: MainTabView()
        case .connectionProblem: ConnectionProblemView()
        }
    }
}
