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

struct RootView: View {
    @State private var selection: AppTab = .home
    @State private var isAddSheetPresented = false

    var body: some View {
        ZStack {
            AppBackground()
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
            AddTransactionPlaceholder()
                .presentationDetents([.large])
        }
    }
}

private struct AddTransactionPlaceholder: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            Text("הוספת הוצאה או הכנסה")
                .font(.title2.weight(.semibold))
            Text("המסך הזה ייבנה בשלב הליבה.")
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.l)
    }
}

#Preview {
    RootView()
        .environment(\.layoutDirection, .rightToLeft)
}
