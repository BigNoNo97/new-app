import SwiftUI
import SnaPayCore

enum HomePeriod: Hashable {
    case week, month, custom
}

struct HomeView: View {
    @Environment(TransactionStore.self) private var store

    @State private var period: HomePeriod = .month
    @State private var customRange = DateInterval(
        start: Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: .now))!,
        end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
    )
    @State private var isPickingRange = false
    @State private var selected: TransactionRow?
    @State private var isShowingQuickLogSetup = false
    @State private var hidesSetupCard = DevicePreferences.hidesQuickLogSetupCard

    private var reportingPeriod: ReportingPeriod {
        switch period {
        case .week: .thisWeek
        case .month: .thisMonth
        case .custom: .custom(customRange)
        }
    }

    private var interval: DateInterval { store.interval(for: reportingPeriod) }
    private var periodTransactions: [TransactionRow] { store.transactions(in: interval) }
    private var totals: PeriodTotals { TransactionSummary.totals(periodTransactions) }
    private var previousTotals: PeriodTotals {
        let previous = TransactionSummary.previousInterval(of: interval, period: reportingPeriod, monthStartDay: store.profile.monthStartDay)
        return TransactionSummary.totals(store.transactions, in: previous)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                SyncStatusBanner(store: store)

                GlassSegmentedControl(
                    selection: $period,
                    segments: [.init(value: .week, title: "השבוע"), .init(value: .month, title: "החודש"), .init(value: .custom, title: "אחר")],
                    identifier: "home.period"
                )

                if period == .custom {
                    Button {
                        isPickingRange = true
                    } label: {
                        Label(rangeText, systemImage: "calendar")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.brand)
                }

                if !store.pendingCaptures.isEmpty {
                    PendingCapturesCard(store: store)
                }

                if showsSetupCard {
                    QuickLogSetupCard(
                        onOpen: { isShowingQuickLogSetup = true },
                        onClose: {
                            withAnimation {
                                hidesSetupCard = true
                                DevicePreferences.hidesQuickLogSetupCard = true
                            }
                        }
                    )
                }

                summaryCard

                if let trip = store.activeTrip {
                    TripSummaryCard(trip: trip, store: store)
                }

                if periodTransactions.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: "עוד אין כאן הוצאות",
                        message: "לחיצה על + מוסיפה הוצאה או הכנסה. עם התיעוד בקליק, תשלומי Apple Pay נכנסים לכאן כמעט לבד."
                    )
                } else {
                    DayGroupedList(groups: TransactionSummary.groupedByDay(periodTransactions), store: store) { selected = $0 }
                }
            }
            .padding(Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .refreshable { await store.refresh() }
        .sheet(item: $selected) { transaction in
            TransactionDetailView(store: store, transaction: transaction)
        }
        .sheet(isPresented: $isPickingRange) {
            DateRangeSheet(range: $customRange)
        }
        .sheet(isPresented: $isShowingQuickLogSetup) {
            QuickLogSetupView(store: store)
        }
        .onChange(of: period) { _, newValue in
            if newValue == .custom { isPickingRange = true }
        }
    }

    /// Until the first Apple Pay payment arrives, unless the user closed the card.
    private var showsSetupCard: Bool {
        store.quickLogFirstCaptureAt == nil && store.profile.quickLogEnabled && !hidesSetupCard
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("שלום, \(store.profile.firstName)")
                    .font(.largeTitle.weight(.bold))
                Text(Date.now.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView()
            }
        }
        .padding(.top, Spacing.s)
    }

    private var periodName: String {
        switch period {
        case .week: "השבוע"
        case .month: "החודש"
        case .custom: "בתקופה"
        }
    }

    private var previousName: String {
        switch period {
        case .week: "מהשבוע שעבר"
        case .month: "מהחודש שעבר"
        case .custom: "מהתקופה הקודמת"
        }
    }

    private var rangeText: String {
        let style = Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.abbreviated)
        let lastDay = customRange.end.addingTimeInterval(-1)
        return "\(customRange.start.formatted(style)) – \(lastDay.formatted(style))"
    }

    private var summaryCard: some View {
        GlassCard(padding: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("הוצאות \(periodName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.string(totals.expenses, currency: store.mainCurrency))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .accessibilityIdentifier("home.totalSpent")
                    if previousTotals.expenses > 0 {
                        comparisonChip
                    }
                }

                IncomeExpenseBar(income: totals.income, expenses: totals.expenses)

                HStack {
                    StatLabel(title: "הכנסות", value: Money.string(totals.income, currency: store.mainCurrency), color: Theme.income)
                    Spacer()
                    StatLabel(title: "מאזן", value: Money.string(totals.balance, currency: store.mainCurrency),
                              color: totals.balance >= 0 ? Theme.income : Theme.expense)
                    Spacer()
                    StatLabel(title: "פעולות", value: "\(totals.count)", color: .primary)
                }
            }
        }
    }

    private var comparisonChip: some View {
        let difference = totals.expenses - previousTotals.expenses
        let isLess = difference <= 0
        let text = "\(Money.string(abs(difference), currency: store.mainCurrency)) \(isLess ? "פחות" : "יותר") \(previousName)"
        return HStack(spacing: 4) {
            Image(systemName: isLess ? "arrow.down" : "arrow.up")
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(isLess ? Theme.income : Theme.expense)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((isLess ? Theme.income : Theme.expense).opacity(0.12), in: .rect(cornerRadius: 8))
    }
}

private struct StatLabel: View {
    let title: LocalizedStringKey
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

/// Two bars: income and expenses, relative to the larger of the two.
struct IncomeExpenseBar: View {
    let income: Decimal
    let expenses: Decimal

    var body: some View {
        let largest = max(income, expenses)
        let incomeShare = largest == 0 ? 0 : NSDecimalNumber(decimal: income / largest).doubleValue
        let expenseShare = largest == 0 ? 0 : NSDecimalNumber(decimal: expenses / largest).doubleValue
        VStack(spacing: 6) {
            bar(share: incomeShare, color: Theme.income)
            bar(share: expenseShare, color: Theme.expense)
        }
        .accessibilityHidden(true)
    }

    private func bar(share: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.12))
                RoundedRectangle(cornerRadius: 4).fill(color)
                    .frame(width: max(proxy.size.width * share, share > 0 ? 8 : 0))
            }
        }
        .frame(height: 8)
    }
}

/// While a trip is on: what it has cost so far, in the trip's currency and the main one.
struct TripSummaryCard: View {
    let trip: CategoryItem
    let store: TransactionStore

    var body: some View {
        let entries = store.transactions.filter { $0.categoryID == trip.id && $0.kind == .expense }
        let inTripCurrency = entries.filter { $0.originalCurrency == trip.tripCurrency }.reduce(Decimal(0)) { $0 + $1.originalAmount }
        let inMain = entries.reduce(Decimal(0)) { $0 + $1.amount }
        GlassCard {
            HStack(spacing: Spacing.m) {
                CategoryBadge(category: trip, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.name)
                        .font(.headline)
                    Text("הוצאות חדשות נרשמות ב-\(trip.tripCurrency ?? "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.string(inTripCurrency, currency: trip.tripCurrency ?? store.mainCurrency))
                        .font(.headline)
                    Text(Money.string(inMain, currency: store.mainCurrency))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("home.trip")
    }
}

/// Pick a custom date range (both days inclusive).
struct DateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var range: DateInterval

    @State private var start: Date
    @State private var end: Date

    init(range: Binding<DateInterval>) {
        _range = range
        _start = State(initialValue: range.wrappedValue.start)
        _end = State(initialValue: range.wrappedValue.end.addingTimeInterval(-1))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.m) {
                DatePicker("מתאריך", selection: $start, in: ...end, displayedComponents: .date)
                DatePicker("עד תאריך", selection: $end, in: start..., displayedComponents: .date)
                Spacer()
                Button("הצגה") {
                    let calendar = Calendar.current
                    let from = calendar.startOfDay(for: start)
                    let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
                    range = DateInterval(start: from, end: to)
                    dismiss()
                }
                .buttonStyle(.primary)
            }
            .padding(Spacing.l)
            .navigationTitle("בחירת תקופה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                    .sharedBackgroundVisibility(.hidden)
            }
        }
        .presentationDetents([.medium])
    }
}
