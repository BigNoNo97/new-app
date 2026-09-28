import SwiftUI

struct NiceToMeetYouView: View {
    @Environment(AppState.self) private var app

    private let features: [(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey)] = [
        ("wave.3.right", "תיעוד בקליק מ-Apple Pay", "משלמים, ומיד קופצת חלונית קטנה לבחירת קטגוריה."),
        ("arrow.triangle.2.circlepath", "הכנסות וחיובים קבועים", "משכורת, שכירות ומנויים נרשמים לבד בכל חודש."),
        ("person.2.fill", "חשבון משותף למשפחה", "כל אחד מתעד את שלו, וכולם רואים את התמונה המלאה."),
        ("airplane", "מטבעות ונסיעות לחו\"ל", "מזינים בדולרים או ביורו, ורואים כמה זה בשקלים כולל עמלה."),
        ("target", "יעדי חיסכון ותקציבים", "מגדירים יעד, ורואים כמה נשאר עד שמגיעים אליו."),
        ("sparkles", "סיכום חודשי", "בסוף כל חודש: לאן הלך הכסף, במבט אחד."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("\(app.profile?.firstName ?? ""), נעים להכיר!")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityIdentifier("nice.title")
                    Text("SnaPay עוזר לך לדעת לאן הולך הכסף, בלי להקליד כל הוצאה מחדש. הנה מה שמחכה לך:")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Spacing.xl)

                VStack(spacing: Spacing.m) {
                    ForEach(features, id: \.symbol) { feature in
                        GlassCard {
                            HStack(alignment: .top, spacing: Spacing.m) {
                                Image(systemName: feature.symbol)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.brand)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.brand.opacity(0.14), in: .rect(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.headline)
                                    Text(feature.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Spacing.m)
        }
        .safeAreaInset(edge: .bottom) {
            Button("נתחיל!") { app.continueFromNiceToMeetYou() }
                .buttonStyle(.primary)
                .padding(Spacing.m)
                .accessibilityIdentifier("nice.continue")
        }
    }
}
