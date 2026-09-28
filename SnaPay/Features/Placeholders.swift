import SwiftUI

// Placeholder tab screens so the navigation shell runs end to end. Each one is replaced
// by the real screen in its build stage (see TASKS.md).

struct GoalsView: View {
    var body: some View {
        PlaceholderScreen(title: "יעדים", message: "כאן יופיעו יעדי החיסכון שלך.")
    }
}

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(TransactionStore.self) private var store
    @State private var isShowingTrips = false

    var body: some View {
        VStack(spacing: 0) {
            PlaceholderScreen(title: "פרופיל", message: "כאן יופיעו הפרטים שלך, הדוחות וההגדרות.")
            // Temporary entries until the profile and settings screens.
            VStack(spacing: Spacing.s) {
                Button {
                    isShowingTrips = true
                } label: {
                    Label("טיולים", systemImage: "airplane")
                }
                .buttonStyle(.glassSecondary)
                .accessibilityIdentifier("profile.trips")
                Button("התנתקות") {
                    Task { await app.signOut() }
                }
                .buttonStyle(.glassSecondary)
                .accessibilityIdentifier("profile.signOut")
            }
            .padding(Spacing.m)
        }
        .sheet(isPresented: $isShowingTrips) {
            TripsView(store: store)
        }
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
