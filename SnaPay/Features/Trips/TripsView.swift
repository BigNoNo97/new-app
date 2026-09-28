import SwiftUI
import SnaPayCore

/// Trips are categories with their own currency and dates: while one is on, new expenses
/// default to its currency and are converted to the main one (card fee included).
struct TripsView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TransactionStore
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("בזמן טיול, הוצאות חדשות נרשמות במטבע של היעד ומומרות לשקלים, כולל עמלת ההמרה של הכרטיס.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if store.trips.isEmpty {
                        EmptyStateView(symbol: "airplane", title: "עוד אין טיולים", message: "טיול חדש מוסיף קטגוריה עם מטבע ותאריכים.")
                    } else {
                        ForEach(store.trips) { trip in
                            GlassCard {
                                HStack(spacing: Spacing.m) {
                                    CategoryBadge(category: trip, size: 48)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(trip.name)
                                            .font(.headline)
                                        Text(dates(of: trip))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(trip.tripCurrency ?? "")
                                        .font(.subheadline.weight(.semibold))
                                    if trip.isActiveTrip(on: .now) {
                                        Text("עכשיו")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Theme.brand, in: .rect(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.m)
            }
            .navigationTitle("טיולים")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגירה") { dismiss() }
                }
                    .sharedBackgroundVisibility(.hidden)
            }
            .safeAreaInset(edge: .bottom) {
                Button("טיול חדש") { isCreating = true }
                    .buttonStyle(.primary)
                    .padding(Spacing.m)
                    .accessibilityIdentifier("trips.new")
            }
            .sheet(isPresented: $isCreating) {
                NewTripSheet(store: store)
            }
        }
    }

    private func dates(of trip: CategoryItem) -> String {
        let style = Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.abbreviated)
        let start = trip.tripStartsOn.flatMap { DayString.date(from: $0) }?.formatted(style) ?? ""
        let end = trip.tripEndsOn.flatMap { DayString.date(from: $0) }?.formatted(style) ?? ""
        return "\(start) – \(end)"
    }
}

struct NewTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: TransactionStore

    @State private var name = ""
    @State private var emoji = "✈️"
    @State private var currency = "USD"
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now))!
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let emojis = ["✈️", "🏖️", "🏔️", "🗽", "🗼", "🏛️", "🌴", "🎿", "🚗", "🚢"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    GlassTextField(title: "שם הטיול", text: $name, kind: .name, identifier: "trip.name")

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("אימוג'י")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(emojis, id: \.self) { option in
                                Button {
                                    emoji = option
                                } label: {
                                    Text(option)
                                        .font(.title3)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(emoji == option ? Theme.brand.opacity(0.2) : .clear, in: .rect(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    CurrencyPickerRow(title: "מטבע היעד", code: $currency)

                    VStack(spacing: Spacing.s) {
                        DatePicker("יציאה", selection: $start, displayedComponents: .date)
                        DatePicker("חזרה", selection: $end, in: start..., displayedComponents: .date)
                    }

                    if let errorMessage {
                        ErrorBanner(message: LocalizedStringKey(errorMessage))
                    }
                }
                .padding(Spacing.m)
            }
            .navigationTitle("טיול חדש")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                    .sharedBackgroundVisibility(.hidden)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    LoadingLabel(title: "יצירת הטיול", isLoading: isSaving)
                }
                .buttonStyle(.primary)
                .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(Spacing.m)
                .accessibilityIdentifier("trip.save")
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await store.createTrip(name: name, emoji: emoji, currency: currency, startsOn: start, endsOn: end)
                dismiss()
            } catch {
                errorMessage = "לא הצלחנו ליצור את הטיול. בדקו את החיבור ונסו שוב."
            }
            isSaving = false
        }
    }
}
