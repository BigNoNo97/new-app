import SwiftUI
import SnaPayCore

enum HomePeriod: Hashable {
    case week, month, custom
}

struct HomeView: View {
    @Environment(TransactionStore.self) private var store
    /// Opens the add sheet (owned by the tab view).
    var onAdd: () -> Void = {}

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
            VStack(alignment: .leading, spacing: 14) {
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
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.brandInk)
                }

                summaryCard

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

                if let trip = store.activeTrip {
                    TripSummaryCard(trip: trip, store: store)
                }

                if periodTransactions.isEmpty {
                    VStack(spacing: Spacing.m) {
                        EmptyStateView(
                            symbol: "wave.3.right",
                            title: "עוד אין הוצאות \(periodName)",
                            message: "אחרי התשלום הבא ב-Apple Pay הוא יופיע כאן. אפשר גם להוסיף הוצאה ידנית."
                        )
                        Button(action: onAdd) {
                            Label("הוספת הוצאה", systemImage: "plus")
                        }
                        .buttonStyle(.primary)
                        .padding(.horizontal, Spacing.m)
                        .accessibilityIdentifier("home.empty.add")
                        if store.quickLogFirstCaptureAt == nil {
                            Button("הגדרת תיעוד בקליק") { isShowingQuickLogSetup = true }
                                .buttonStyle(.text)
                        }
                    }
                } else {
                    DayGroupedList(groups: TransactionSummary.groupedByDay(periodTransactions), store: store) { selected = $0 }
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, Spacing.gutter)
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
        HStack(spacing: Spacing.sm) {
            MemberAvatar(id: store.userID, name: store.profile.firstName, size: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text(Date.now.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).weekday(.wide).day().month(.wide)))
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                Text("\(greeting), \(store.profile.firstName)")
                    .font(Typography.title2)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if store.isRefreshing {
                ProgressView()
            }
            if store.isShared {
                HStack(spacing: Spacing.s) {
                    HStack(spacing: -8) {
                        ForEach(store.members.prefix(3)) { member in
                            MemberAvatar(id: member.id, name: member.firstName, size: 24)
                                .overlay(Circle().strokeBorder(Theme.glassStrong, lineWidth: 2))
                        }
                    }
                    Text("משותף")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
                .glassSurface(radius: Radius.field)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("חשבון משותף פעיל")
            }
        }
        .padding(.top, Spacing.s)
    }

    /// "בוקר טוב" / "צהריים טובים" / "ערב טוב" / "לילה טוב" by the hour.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "בוקר טוב"
        case 12..<17: "צהריים טובים"
        case 17..<22: "ערב טוב"
        default: "לילה טוב"
        }
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

    private var monthName: String {
        Date.now.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).month(.wide))
    }

    /// "1–28 בספט׳": the part of the period so far.
    private var intervalText: String {
        let style = Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.abbreviated)
        let last = min(interval.end.addingTimeInterval(-1), .now)
        let calendar = Calendar.current
        if calendar.isDate(interval.start, equalTo: last, toGranularity: .month) {
            return "\(calendar.component(.day, from: interval.start))–\(last.formatted(style))"
        }
        return "\(interval.start.formatted(style)) – \(last.formatted(style))"
    }

    private var summaryCard: some View {
        GlassCard(padding: Spacing.gutter) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("הוצאות \(periodName)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(intervalText)
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                HStack(alignment: .bottom, spacing: Spacing.s) {
                    AmountText(text: Money.string(totals.expenses, currency: store.mainCurrency))
                        .accessibilityIdentifier("home.totalSpent")
                    Spacer(minLength: 0)
                    if previousTotals.expenses > 0 {
                        comparisonChip
                            .padding(.bottom, 4)
                    }
                }
                .padding(.top, -6)

                if totals.count == 0 {
                    Text(period == .month ? "\(monthName) רק התחיל. כל הוצאה תופיע כאן." : "כל הוצאה בתקופה הזו תופיע כאן.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    IncomeExpenseBar(income: totals.income, expenses: totals.expenses)

                    HStack {
                        legend(color: Theme.expense, title: "הוצאות", value: nil)
                        Spacer()
                        legend(color: Theme.brand, title: "הכנסות", value: Money.string(totals.income, currency: store.mainCurrency))
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private func legend(color: Color, title: LocalizedStringKey, value: String?) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(Theme.textSecondary)
            if let value {
                Text(value).fontWeight(.semibold).monospacedDigit().foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private var comparisonChip: some View {
        let difference = totals.expenses - previousTotals.expenses
        let isLess = difference <= 0
        let text = "\(Money.string(abs(difference), currency: store.mainCurrency)) \(isLess ? "פחות" : "יותר") \(previousName)"
        return HStack(spacing: 4) {
            Image(systemName: isLess ? "arrow.down" : "arrow.up")
                .font(.caption.weight(.bold))
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(isLess ? Theme.brandInk : Theme.expense)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(isLess ? Theme.brandTint : Theme.expenseTint, in: .rect(cornerRadius: Radius.chip))
    }
}

/// One bar split between expenses (red) and income (green), in proportion.
struct IncomeExpenseBar: View {
    let income: Decimal
    let expenses: Decimal

    var body: some View {
        let total = income + expenses
        let expenseShare = total == 0 ? 0.5 : NSDecimalNumber(decimal: expenses / total).doubleValue
        GeometryReader { proxy in
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 5).fill(total == 0 ? Theme.track : Theme.expense)
                    .frame(width: max((proxy.size.width - 3) * expenseShare, expenses > 0 ? 6 : 0))
                RoundedRectangle(cornerRadius: 5).fill(total == 0 ? Theme.track : Theme.brand.opacity(0.9))
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
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
        HStack(spacing: Spacing.sm) {
            CategoryBadge(category: trip, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trip.name) · \(CurrencyNames.symbol(for: trip.tripCurrency ?? store.mainCurrency))")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(datesText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(text: Money.string(inTripCurrency, currency: trip.tripCurrency ?? store.mainCurrency, alwaysShowCents: true),
                           font: .title3.weight(.bold))
                Text("≈ \(Money.string(inMain, currency: store.mainCurrency))")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Spacing.m)
        .background(
            LinearGradient(colors: [Color(hex: trip.color).opacity(0.18), Theme.glass], startPoint: .leading, endPoint: .trailing),
            in: .rect(cornerRadius: Radius.card)
        )
        .glassSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.trip")
    }

    /// "24 בספט׳ – 2 באוק׳ · נשארו 4 ימים".
    private var datesText: String {
        let calendar = Calendar.current
        let style = Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.abbreviated)
        guard let start = trip.tripStartsOn.flatMap({ DayString.date(from: $0) }) else { return "" }
        guard let end = trip.tripEndsOn.flatMap({ DayString.date(from: $0) }) else { return "מ-\(start.formatted(style))" }
        let left = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: end).day ?? 0
        let remaining = left <= 0 ? "יום אחרון" : (left == 1 ? "נשאר יום אחד" : "נשארו \(left) ימים")
        return "\(start.formatted(style)) – \(end.formatted(style)) · \(remaining)"
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
                    .tint(Theme.brand)
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
