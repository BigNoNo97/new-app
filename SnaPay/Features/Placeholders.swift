import SwiftUI

// Placeholder tab screens so the navigation shell runs end to end. Each one is replaced
// by the real screen in its build stage (see TASKS.md).

struct HomeView: View {
    var body: some View {
        PlaceholderScreen(title: "בית", message: "כאן יופיעו ההוצאות האחרונות והסיכום לתקופה.")
    }
}

struct ExpensesView: View {
    var body: some View {
        PlaceholderScreen(title: "הוצאות", message: "כאן תופיע הרשימה המלאה, עם סינון, ייבוא וייצוא.")
    }
}

struct GoalsView: View {
    var body: some View {
        PlaceholderScreen(title: "יעדים", message: "כאן יופיעו יעדי החיסכון שלך.")
    }
}

struct ProfileView: View {
    var body: some View {
        PlaceholderScreen(title: "פרופיל", message: "כאן יופיעו הפרטים שלך, הדוחות וההגדרות.")
    }
}

private struct PlaceholderScreen: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                GlassCard {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.m)
        }
    }
}
