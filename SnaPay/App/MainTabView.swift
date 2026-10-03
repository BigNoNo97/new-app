import SwiftUI
import SnaPayCore

enum AppTab: CaseIterable, Hashable {
    case home, expenses, goals, profile

    var title: LocalizedStringKey {
        switch self {
        case .home: "בית"
        case .expenses: "הוצאות"
        case .goals: "יעדים"
        case .profile: "פרופיל"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .expenses: "list.bullet.rectangle"
        case .goals: "flag"
        case .profile: "person"
        }
    }
}

/// The signed-in app: tab content with the floating bottom bar.
struct MainTabView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var isAddSheetPresented = false
    @State private var shownInvite: PendingInvite?
    /// Invites the user put off with "לא עכשיו" (asked again on the next launch).
    @State private var postponedInvites: Set<UUID> = []

    var body: some View {
        if let store = app.store {
            tabs(store: store)
                .environment(store)
        } else {
            LaunchView()
        }
    }

    private func tabs(store: TransactionStore) -> some View {
        ZStack {
            Group {
                switch selection {
                case .home: HomeView(onAdd: { isAddSheetPresented = true })
                case .expenses: ExpensesView()
                case .goals: GoalsView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar(selection: $selection) {
                isAddSheetPresented = true
            }
            .padding(.horizontal, Spacing.m)
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddTransactionSheet(store: store)
                .presentationDetents([.large])
        }
        // Payments logged from the quick-log card while the app was in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await store.syncQuickLog()
                    await QuickLogLiveActivity.endResolved()
                    await app.loadPendingInvites()
                }
            }
        }
        // A partner's new expense (push) while the app is open, or a tapped notification.
        .onReceive(NotificationCenter.default.publisher(for: .remoteActivity)) { _ in
            selection = .home
            Task { await store.refresh() }
        }
        .sheet(item: $shownInvite, onDismiss: {
            // Still pending after the sheet closed: "לא עכשיו".
            postponedInvites.formUnion(app.pendingInvites.map(\.id))
        }) { invite in
            InviteReceivedSheet(invite: invite)
        }
        .onChange(of: app.pendingInvites, initial: true) { _, invites in
            if shownInvite == nil, let next = invites.first(where: { !postponedInvites.contains($0.id) }) {
                shownInvite = next
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickLogDidChange)) { _ in
            store.reloadQuickLogInbox()
            Task { await QuickLogLiveActivity.endResolved() }
        }
    }
}
