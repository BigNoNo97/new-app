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
    @State private var isShowingQuickLogSetup = false

    var body: some View {
        VStack(spacing: 0) {
            PlaceholderScreen(title: "פרופיל", message: "כאן יופיעו הפרטים שלך, הדוחות וההגדרות.")
            // Temporary entries until the profile and settings screens.
            VStack(spacing: Spacing.s) {
                Toggle(isOn: Binding(
                    get: { store.profile.quickLogEnabled },
                    set: { enabled in Task { await store.setQuickLogEnabled(enabled) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("תיעוד בקליק")
                            .font(.body.weight(.medium))
                        Text("חלונית לבחירת קטגוריה אחרי תשלום ב-Apple Pay")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .toggleStyle(.rounded)
                .padding(Spacing.m)
                .glassSurface(radius: Radius.control)
                .accessibilityIdentifier("profile.quickLog")
                Button {
                    isShowingQuickLogSetup = true
                } label: {
                    Label("הגדרת האוטומציה", systemImage: "wave.3.right")
                }
                .buttonStyle(.glassSecondary)
                .accessibilityIdentifier("profile.quickLogSetup")
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
        .sheet(isPresented: $isShowingQuickLogSetup) {
            QuickLogSetupView(store: store)
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
                    .font(Typography.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
                GlassCard {
                    Text(message)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Spacing.m)
        }
    }
}
