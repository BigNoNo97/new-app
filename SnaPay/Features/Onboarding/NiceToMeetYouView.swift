import SwiftUI

struct NiceToMeetYouView: View {
    @Environment(AppState.self) private var app

    private let features: [(symbol: String, color: UInt32, title: LocalizedStringKey, detail: LocalizedStringKey)] = [
        ("wave.3.right", 0x2FB36D, "תיעוד בקליק מ-Apple Pay", "משלמים, בוחרים קטגוריה, וזהו."),
        ("arrow.triangle.2.circlepath", 0x3B82F6, "הכנסות וחיובים קבועים", "משכורת, שכירות ומנויים נרשמים לבד."),
        ("person.2", 0xE056B0, "חשבון משותף למשפחה", "כל אחד מתעד את שלו, כולם רואים הכול."),
        ("globe", 0x0EA5E9, "מטבעות ונסיעות לחו\"ל", "המרה אוטומטית, כולל עמלת הכרטיס."),
        ("target", 0x84B814, "יעדי חיסכון ותקציבים", "יודעים כמה נשאר ומתי מגיעים ליעד."),
        ("chart.bar", 0xF59E0B, "סיכום חודשי", "החודש שלך בכמה כרטיסים קלילים."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("\(app.profile?.firstName ?? ""), נעים להכיר!")
                        .font(Typography.largeTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("nice.title")
                    Text("\u{200F}SnaPay הופך כל תשלום לרישומה מסודרת, מחלק לקטגוריות ומראה לך לאן הולך הכסף, לבד או עם המשפחה.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, Spacing.xl)

                VStack(spacing: Spacing.cardGap) {
                    ForEach(features, id: \.symbol) { feature in
                        GlassCard {
                            HStack(spacing: Spacing.m) {
                                FeatureIcon(symbol: feature.symbol, color: Color(uiColor: UIColor(hex: feature.color)), size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.headline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(feature.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.m)
        }
        .safeAreaBar(edge: .bottom) {
            Button("נתחיל!") { app.continueFromNiceToMeetYou() }
                .buttonStyle(.primary)
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.s)
                .accessibilityIdentifier("nice.continue")
        }
    }
}
