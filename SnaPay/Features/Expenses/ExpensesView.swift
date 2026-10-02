import SwiftUI
import SnaPayCore

/// Every transaction, with search, filters and CSV export (design: `expenses`, `expmenu`).
struct ExpensesView: View {
    @Environment(TransactionStore.self) private var store

    @State private var filter = TransactionFilter()
    @State private var isShowingFilters = false
    @State private var selected: TransactionRow?
    @State private var isLoadingOlder = false
    @State private var isShowingImportNotice = false

    private var filtered: [TransactionRow] {
        filter.apply(to: store.transactions) { store.category($0)?.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    Text("הוצאות")
                        .font(Typography.largeTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Menu {
                        Button {
                            isShowingImportNotice = true
                        } label: {
                            Label("ייבוא מעו\"ש", systemImage: "square.and.arrow.down")
                        }
                        ShareLink(item: exportFile(), preview: SharePreview("SnaPay.csv")) {
                            Label("ייצוא לקובץ", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .glassSurface(radius: Radius.field, interactive: true)
                    }
                    .accessibilityLabel(Text("אפשרויות"))
                    .accessibilityIdentifier("expenses.menu")
                }
                .padding(.top, Spacing.s)

                SyncStatusBanner(store: store)

                HStack(spacing: Spacing.s) {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.textTertiary)
                        TextField("חיפוש לפי בית עסק, הערה או סכום", text: $filter.searchText)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("expenses.search")
                    }
                    .fieldSurface()

                    Button {
                        isShowingFilters = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.medium))
                            .foregroundStyle(filter.activeCount > 0 ? Theme.brandInk : Theme.textPrimary)
                            .frame(width: Metrics.fieldHeight, height: Metrics.fieldHeight)
                            .background(filter.activeCount > 0 ? Theme.brandTint : Theme.field, in: .rect(cornerRadius: Radius.field))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.field)
                                    .strokeBorder(filter.activeCount > 0 ? Theme.brand.opacity(0.55) : Theme.stroke, lineWidth: 1)
                            }
                            .overlay(alignment: .topLeading) {
                                if filter.activeCount > 0 {
                                    Text("\(filter.activeCount)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Theme.onButtonPrimary)
                                        .frame(width: 18, height: 18)
                                        .background(Theme.buttonPrimary, in: .rect(cornerRadius: 6))
                                        .offset(x: -4, y: -4)
                                }
                            }
                    }
                    .accessibilityLabel(Text("סינון"))
                    .accessibilityIdentifier("expenses.filter")
                }

                if !filtered.isEmpty {
                    let totals = TransactionSummary.totals(filtered)
                    HStack {
                        Text(totals.count == 1 ? "עסקה אחת" : "\(totals.count) עסקאות")
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("סה״כ")
                                .foregroundStyle(Theme.textSecondary)
                            Text(Money.string(totals.expenses, currency: store.mainCurrency))
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("expenses.filteredTotal")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.top, Spacing.xs)
                }

                if filtered.isEmpty {
                    EmptyStateView(
                        symbol: filter.isEmpty ? "doc.text" : "slider.horizontal.3",
                        title: filter.isEmpty ? "אין כאן הוצאות עדיין" : "לא נמצאו תוצאות",
                        message: filter.isEmpty
                            ? "לחיצה על + מוסיפה את ההוצאה הראשונה."
                            : "נסו לשנות את החיפוש או את הסינון."
                    )
                } else {
                    DayGroupedList(groups: TransactionSummary.groupedByDay(filtered), store: store) { selected = $0 }
                }

                if store.hasOlderTransactions && filter.dateRange == nil {
                    Button {
                        isLoadingOlder = true
                        Task {
                            await store.loadOlder()
                            isLoadingOlder = false
                        }
                    } label: {
                        LoadingLabel(title: "טעינת הוצאות ישנות יותר", isLoading: isLoadingOlder)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .buttonStyle(.glassSecondary)
                    .disabled(isLoadingOlder)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refresh() }
        .sheet(isPresented: $isShowingFilters) {
            FilterSheet(filter: $filter, store: store)
        }
        .sheet(item: $selected) { transaction in
            TransactionDetailView(store: store, transaction: transaction)
        }
        .alert("ייבוא מעו\"ש", isPresented: $isShowingImportNotice) {
            Button("הבנתי", role: .cancel) {}
        } message: {
            Text("ייבוא קבצי עו\"ש מהבנקים יגיע בעדכון הקרוב.")
        }
    }

    /// Writes the filtered list to a temporary CSV for the share sheet.
    private func exportFile() -> URL {
        let csv = CSVExporter.csv(
            filtered,
            categoryName: { store.category($0)?.name },
            memberName: { store.memberName($0) }
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SnaPay.csv")
        try? csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}

/// All filters in one sheet (design: `filter`).
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: TransactionFilter
    let store: TransactionStore

    private enum DatePreset: Hashable { case week, month, threeMonths, custom }

    @State private var draft: TransactionFilter
    @State private var datePreset: DatePreset?
    @State private var from: Date
    @State private var to: Date
    @State private var minText: String
    @State private var maxText: String

    init(filter: Binding<TransactionFilter>, store: TransactionStore) {
        _filter = filter
        self.store = store
        let current = filter.wrappedValue
        _draft = State(initialValue: current)
        _datePreset = State(initialValue: current.dateRange == nil ? nil : .custom)
        _from = State(initialValue: current.dateRange?.start ?? Calendar.current.date(byAdding: .month, value: -1, to: .now)!)
        _to = State(initialValue: current.dateRange?.end.addingTimeInterval(-1) ?? .now)
        _minText = State(initialValue: current.minAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _maxText = State(initialValue: current.maxAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
    }

    private var kindSelection: Binding<EntryKind?> {
        Binding(
            get: { draft.kinds.count == 1 ? draft.kinds.first : nil },
            set: { draft.kinds = $0.map { [$0] } ?? [] }
        )
    }

    private var currencies: [String] {
        Array(Set(store.transactions.map(\.originalCurrency))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("סינון")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack {
                    Button("איפוס") {
                        filter = TransactionFilter(searchText: filter.searchText)
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.brandInk)
                    .accessibilityIdentifier("filter.reset")
                    Spacer()
                    IconButton(symbol: "xmark", label: "סגירה") { dismiss() }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.s)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    section("סוג") {
                        GlassSegmentedControl(
                            selection: kindSelection,
                            segments: [.init(value: nil, title: "הכול"), .init(value: .expense, title: "הוצאות"), .init(value: .income, title: "הכנסות")],
                            identifier: "filter.kind"
                        )
                    }

                    section("קטגוריה") {
                        FlowChips(items: store.categories.filter { !$0.isArchived }.map { ($0.id, "\($0.emoji) \($0.name)") },
                                  selection: $draft.categoryIDs)
                    }

                    section("תאריך") {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            FlowLayout(spacing: Spacing.s) {
                                presetChip("השבוע", .week)
                                presetChip("החודש", .month)
                                presetChip("3 חודשים", .threeMonths)
                                presetChip("טווח מותאם", .custom)
                            }
                            if datePreset == .custom {
                                DatePicker("מתאריך", selection: $from, in: ...to, displayedComponents: .date)
                                DatePicker("עד תאריך", selection: $to, in: from..., displayedComponents: .date)
                            }
                        }
                        .tint(Theme.brand)
                    }

                    section("סכום") {
                        HStack(spacing: Spacing.sm) {
                            amountField("\(CurrencyNames.symbol(for: store.mainCurrency))0", text: $minText)
                            Text("עד")
                                .foregroundStyle(Theme.textSecondary)
                            amountField("ללא הגבלה", text: $maxText)
                        }
                    }

                    if store.isShared {
                        section("בן משפחה") {
                            FlowLayout(spacing: Spacing.s) {
                                ForEach(store.members) { member in
                                    memberChip(member)
                                }
                            }
                        }
                    }

                    if currencies.count > 1 {
                        section("מטבע") {
                            FlowChips(items: currencies.map { ($0, $0) }, selection: $draft.currencies)
                        }
                    }

                    section("מקור") {
                        FlowChips(
                            items: [TransactionSource.applePay, .manual, .receipt, .recurring, .imported].map { ($0, TransactionSourceStyle.name(for: $0)) },
                            selection: $draft.sources
                        )
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.m)
            }
            .safeAreaInset(edge: .bottom) {
                Button("הצגת \(preview.count) תוצאות") {
                    filter = applied
                    dismiss()
                }
                .buttonStyle(.primary)
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.s)
                .accessibilityIdentifier("filter.apply")
            }
        }
        .designSheet()
    }

    private func presetChip(_ title: LocalizedStringKey, _ preset: DatePreset) -> some View {
        FilterChip(title: title, isOn: datePreset == preset) {
            datePreset = datePreset == preset ? nil : preset
        }
    }

    private func memberChip(_ member: HouseholdMember) -> some View {
        let isOn = draft.userIDs.contains(member.id)
        return Button {
            if isOn { draft.userIDs.remove(member.id) } else { draft.userIDs.insert(member.id) }
        } label: {
            HStack(spacing: 6) {
                MemberAvatar(id: member.id, name: member.firstName, size: 22)
                Text(member.firstName)
            }
            .filterChipStyle(isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var applied: TransactionFilter {
        var result = draft
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        switch datePreset {
        case nil:
            result.dateRange = nil
        case .week:
            result.dateRange = store.interval(for: .thisWeek)
        case .month:
            result.dateRange = store.interval(for: .thisMonth)
        case .threeMonths:
            result.dateRange = DateInterval(start: calendar.date(byAdding: .month, value: -3, to: today)!, end: tomorrow)
        case .custom:
            result.dateRange = DateInterval(start: calendar.startOfDay(for: from),
                                            end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to))!)
        }
        let minValue = AmountInput.decimal(from: minText)
        let maxValue = AmountInput.decimal(from: maxText)
        result.minAmount = minText.isEmpty ? nil : minValue
        result.maxAmount = maxText.isEmpty ? nil : maxValue
        return result
    }

    private var preview: [TransactionRow] {
        applied.apply(to: store.transactions) { store.category($0)?.name }
    }

    /// Shows "," between thousands while typing; the binding keeps the plain number.
    private func amountField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: Binding(
            get: { AmountInput.grouped(text.wrappedValue) },
            set: { text.wrappedValue = AmountInput.normalized($0) }
        ))
            .keyboardType(.decimalPad)
            .monospacedDigit()
            .fieldSurface()
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }
}

/// Multi-select chips (rounded rectangles) that wrap onto new lines.
struct FlowChips<ID: Hashable>: View {
    let items: [(ID, String)]
    @Binding var selection: Set<ID>

    var body: some View {
        FlowLayout(spacing: Spacing.s) {
            ForEach(items, id: \.0) { item in
                let id = item.0
                let title = item.1
                let isOn = selection.contains(id)
                Button {
                    if isOn { selection.remove(id) } else { selection.insert(id) }
                } label: {
                    Text(title)
                        .filterChipStyle(isOn: isOn)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("chip.\(title)")
            }
        }
    }
}

/// A single on/off chip.
struct FilterChip: View {
    let title: LocalizedStringKey
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).filterChipStyle(isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension View {
    /// Chip look from the design: 40pt, radius 12; selected is green-tinted with a green border.
    func filterChipStyle(isOn: Bool) -> some View {
        self
            .font(.subheadline.weight(isOn ? .bold : .medium))
            .foregroundStyle(isOn ? Theme.brandInk : Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(isOn ? Theme.brandTint : Theme.fillStrong, in: .rect(cornerRadius: Radius.chip))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.chip)
                    .strokeBorder(isOn ? Theme.brand.opacity(0.55) : .clear, lineWidth: 1)
            }
    }
}

/// Lays children out left to right (right to left in Hebrew), wrapping to new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
