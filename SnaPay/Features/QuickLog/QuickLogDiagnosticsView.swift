import ActivityKit
import SwiftUI

/// The quick-log diagnostics log (`QuickLogStorage.log`), newest first, with the state of every
/// quick-log card iOS still knows. Opened by a long press on the status in the setup guide, for
/// a screenshot when the card doesn't behave.
struct QuickLogDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [QuickLogStorage.LogEntry] = []
    @State private var cards: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SheetHeader(title: "יומן אבחון") { dismiss() }
                    .padding(.top, Spacing.l)

                Text(ActivityAuthorizationInfo().areActivitiesEnabled ? "Live Activities מופעלות" : "Live Activities כבויות בהגדרות")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(cards, id: \.self) { card in
                    Text(card)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    if entries.isEmpty {
                        Text("עוד אין אירועים")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(Array(entries.reversed().enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Text(entry.date.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.abbreviated).hour().minute().second()))
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                            Text(entry.text)
                                .font(.footnote)
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface()
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.l)
        }
        .designSheet()
        .presentationDetents([.large])
        .task {
            entries = QuickLogStorage.loadLog()
            var states: [String] = []
            for activity in Activity<QuickLogActivityAttributes>.activities {
                states.append("כרטיס \(activity.attributes.paymentID.uuidString.prefix(8)): \(activity.activityState)")
            }
            cards = states.isEmpty ? ["אין כרטיסים פתוחים"] : states
        }
    }
}
