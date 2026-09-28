import SwiftUI

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
    @State private var selection: AppTab = .home
    @State private var isAddSheetPresented = false

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
                case .home: HomeView()
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
    }
}
