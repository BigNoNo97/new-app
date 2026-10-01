import SwiftUI
import SnaPayCore

// Placeholder tab screens so the navigation shell runs end to end. Each one is replaced
// by the real screen in its build stage (see TASKS.md).

struct GoalsView: View {
    var body: some View {
        PlaceholderScreen(title: "יעדים", message: "כאן יופיעו יעדי החיסכון שלך.")
    }
}

/// Profile (design: `profile`). The reports, charts and budgets arrive with stage 8; for now:
/// who I am, the shared account at a glance, and the way into settings.
struct ProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(TransactionStore.self) private var store
    @State private var isShowingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("פרופיל")
                    .font(Typography.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, Spacing.s)

                GlassCard(padding: Spacing.gutter) {
                    HStack(spacing: Spacing.sm) {
                        MemberAvatar(id: store.userID, name: store.profile.firstName, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.profile.fullName)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(store.isShared ? "חשבון משותף · \(store.members.count) שותפים" : "חשבון אישי")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        IconButton(symbol: "gearshape", label: "הגדרות") { isShowingSettings = true }
                            .accessibilityIdentifier("profile.settings")
                    }
                }

                if !store.isShared {
                    GlassCard {
                        HStack(alignment: .top, spacing: Spacing.m) {
                            FeatureIcon(symbol: "person.2", color: Color(uiColor: UIColor(hex: 0xE056B0)), size: 40)
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                Text("מנהלים את הכסף יחד?")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("מזמינים בן או בת זוג, וכל אחד רואה את ההוצאות של כולם.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                Button("הזמנה לחשבון משותף") { isShowingSettings = true }
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.brandInk)
                                    .accessibilityIdentifier("profile.invite")
                            }
                        }
                    }
                }

                GlassCard {
                    HStack(spacing: Spacing.m) {
                        FeatureIcon(symbol: "chart.bar", color: Color(uiColor: UIColor(hex: 0xF59E0B)), size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("דוחות וגרפים")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Text("התפלגות לפי קטגוריות, השוואה בין חודשים וסיכום חודשי. בקרוב.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.xl)
        }
        .fullScreenCover(isPresented: $isShowingSettings) {
            SettingsView(store: store)
                .environment(app)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
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
