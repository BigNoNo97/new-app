import SwiftUI
import SnaPayCore

/// Walks the user through the one-time Shortcuts automation that powers quick-log, then waits
/// for the first payment to arrive.
struct QuickLogSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let store: TransactionStore

    private let steps: [(symbol: String, text: LocalizedStringKey)] = [
        ("square.stack.3d.up.fill", "פותחים את אפליקציית **קיצורים** ועוברים ללשונית **אוטומציה**."),
        ("plus.rectangle.fill", "לוחצים על **+** ובוחרים **עסקה** (Transaction)."),
        ("creditcard.fill", "מסמנים את הכרטיסים שמשלמים איתם ב-Apple Pay, ובוחרים **הפעלה מיידית**."),
        ("wand.and.stars", "בוחרים **אוטומציה ריקה חדשה**, מחפשים **SnaPay** ומוסיפים את הפעולה **תיעוד תשלום**."),
        ("arrow.left.arrow.right", "בשדות הפעולה בוחרים את המשתנים של העסקה: **סכום**, **סוחר** ו**כרטיס**. זהו, אפשר לשמור."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("תיעוד בקליק")
                            .font(.largeTitle.weight(.bold))
                        Text("אחרי כל תשלום ב-Apple Pay קופצת חלונית קטנה, ובלחיצה אחת ההוצאה נשמרת בקטגוריה הנכונה. מגדירים את זה פעם אחת, בדקה.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    statusCard

                    VStack(spacing: Spacing.s) {
                        ForEach(steps, id: \.symbol) { step in
                            GlassCard {
                                HStack(alignment: .top, spacing: Spacing.m) {
                                    Image(systemName: step.symbol)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.brand)
                                        .frame(width: 40, height: 40)
                                        .background(Theme.brand.opacity(0.14), in: .rect(cornerRadius: 12))
                                    Text(step.text)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    Text("החלונית מופיעה רק כשמשלמים בכרטיסים שבחרתם. אם היא לא הופיעה, אפשר לסווג את התשלום אחר כך במסך הבית.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(Spacing.m)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    openURL(URL(string: "shortcuts://")!)
                } label: {
                    Label("פתיחת קיצורים", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.primary)
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.s)
                .accessibilityIdentifier("quicklog.openShortcuts")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגירה") { dismiss() }
                }
                    .sharedBackgroundVisibility(.hidden)
            }
            .task { store.reloadQuickLogInbox() }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        if !store.profile.quickLogEnabled {
            status(symbol: "pause.circle.fill", color: .secondary,
                   title: "התיעוד בקליק כבוי",
                   detail: "אפשר להפעיל אותו בפרופיל. עד אז, החלונית לא תקפוץ אחרי תשלום.")
        } else if let first = store.quickLogFirstCaptureAt {
            status(symbol: "checkmark.circle.fill", color: Theme.brand,
                   title: "מעולה, זה עובד!",
                   detail: "התשלום הראשון נקלט ב\(first.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.wide).hour().minute())).")
        } else {
            GlassCard {
                HStack(spacing: Spacing.m) {
                    Group {
                        // A spinning indicator never lets UI tests see the app idle.
                        if AppConfig.isUITesting {
                            Image(systemName: "hourglass")
                                .font(.title2)
                                .foregroundStyle(Theme.brand)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("מחכים לתשלום הראשון")
                            .font(.headline)
                        Text("אחרי ההגדרה, שלמו במשהו קטן ב-Apple Pay. כשהחלונית תקפוץ, יופיע כאן אישור.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("quicklog.status.waiting")
        }
    }

    private func status(symbol: String, color: Color, title: LocalizedStringKey, detail: String) -> some View {
        GlassCard {
            HStack(spacing: Spacing.m) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("quicklog.status")
    }
}
