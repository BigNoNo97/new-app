import SwiftUI
import WidgetKit

struct SpendEntry: TimelineEntry, Sendable {
    let date: Date
    let spentThisMonth: Decimal
}

struct SpendProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpendEntry {
        SpendEntry(date: .now, spentThisMonth: 3_453)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpendEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendEntry>) -> Void) {
        // Real data comes from the shared App Group store in the "extras" stage.
        completion(Timeline(entries: [placeholder(in: context)], policy: .after(.now.addingTimeInterval(60 * 30))))
    }
}

struct SpendWidgetView: View {
    let entry: SpendEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("הוצאת החודש")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.spentThisMonth, format: .currency(code: "ILS").precision(.fractionLength(0)))
                .font(.title2.weight(.semibold))
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SnaPaySpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SnaPaySpendWidget", provider: SpendProvider()) { entry in
            SpendWidgetView(entry: entry)
        }
        .configurationDisplayName("הוצאת החודש")
        .description("כמה הוצאת החודש, במבט אחד.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SnaPayWidgetBundle: WidgetBundle {
    var body: some Widget {
        SnaPaySpendWidget()
        QuickLogActivityWidget()
    }
}
