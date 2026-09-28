import SwiftUI
import SnaPayCore

/// Every transaction, with search, filters and CSV export.
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
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack {
                    Text("הוצאות")
                        .font(.largeTitle.weight(.bold))
                    Spacer()
                    Menu {
                        ShareLink(item: exportFile(), preview: SharePreview("SnaPay.csv")) {
                            Label("ייצוא לקובץ", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            isShowingImportNotice = true
                        } label: {
                            Label("ייבוא מעו\"ש", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.control))
                    }
                    .accessibilityLabel(Text("אפשרויות"))
                    .accessibilityIdentifier("expenses.menu")
                }
                .padding(.top, Spacing.s)

                SyncStatusBanner(store: store)

                HStack(spacing: Spacing.s) {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("חיפוש לפי בית עסק, הערה או קטגוריה", text: $filter.searchText)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("expenses.search")
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .glassEffect(.regular, in: .rect(cornerRadius: Radius.control))

                    Button {
                        isShowingFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(filter.activeCount > 0 ? .white : .primary)
                            .frame(width: 48, height: 48)
                            .background(filter.activeCount > 0 ? Theme.brand : .clear, in: .rect(cornerRadius: Radius.control))
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.control))
                            .overlay(alignment: .topLeading) {
                                if filter.activeCount > 0 {
                                    Text("\(filter.activeCount)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Theme.expense, in: .rect(cornerRadius: 6))
                                        .offset(x: -4, y: -4)
                                }
                            }
                    }
                    .accessibilityLabel(Text("סינון"))
                    .accessibilityIdentifier("expenses.filter")
                }

                if !filter.isEmpty {
                    let totals = TransactionSummary.totals(filtered)
                    HStack {
                        Text("\(totals.count) תוצאות")
                        Spacer()
                        Text("הוצאות \(Money.string(totals.expenses, currency: store.mainCurrency))")
                            .accessibilityIdentifier("expenses.filteredTotal")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                if filtered.isEmpty {
                    EmptyStateView(
                        symbol: filter.isEmpty ? "tray" : "line.3.horizontal.decrease",
                        title: filter.isEmpty ? "עוד אין הוצאות" : "לא נמצאו תוצאות",
                        message: filter.isEmpty ? "לחיצה על + מוסיפה את ההוצאה הראשונה." : "נסו לשנות את החיפוש או את הסינון."
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
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.glassSecondary)
                    .disabled(isLoadingOlder)
                }
            }
            .padding(Spacing.m)
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

/// All filters in one sheet.
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: TransactionFilter
    let store: TransactionStore

    @State private var draft: TransactionFilter
    @State private var usesDates: Bool
    @State private var from: Date
    @State private var to: Date
    @State private var minText: String
    @State private var maxText: String

    init(filter: Binding<TransactionFilter>, store: TransactionStore) {
        _filter = filter
        self.store = store
        let current = filter.wrappedValue
        _draft = State(initialValue: current)
        _usesDates = State(initialValue: current.dateRange != nil)
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    GlassSegmentedControl(
                        selection: kindSelection,
                        segments: [.init(value: nil, title: "הכל"), .init(value: .expense, title: "הוצאות"), .init(value: .income, title: "הכנסות")],
                        identifier: "filter.kind"
                    )

                    section("קטגוריות") {
                        FlowChips(items: store.categories.map { ($0.id, "\($0.emoji) \($0.name)") }, selection: $draft.categoryIDs)
                    }

                    if store.isShared {
                        section("מי הזין") {
                            FlowChips(items: store.members.map { ($0.id, $0.firstName) }, selection: $draft.userIDs)
                        }
                    }

                    if currencies.count > 1 {
                        section("מטבע") {
                            FlowChips(items: currencies.map { ($0, $0) }, selection: $draft.currencies)
                        }
                    }

                    section("מקור") {
                        FlowChips(
                            items: [TransactionSource.manual, .applePay, .recurring, .receipt, .imported].map { ($0, CSVExporter.sourceName($0)) },
                            selection: $draft.sources
                        )
                    }

                    section("תאריכים") {
                        VStack(spacing: Spacing.s) {
                            Toggle("טווח תאריכים", isOn: $usesDates.animation())
                                .toggleStyle(.rounded)
                            if usesDates {
                                DatePicker("מתאריך", selection: $from, in: ...to, displayedComponents: .date)
                                DatePicker("עד תאריך", selection: $to, in: from..., displayedComponents: .date)
                            }
                        }
                    }

                    section("סכום") {
                        HStack(spacing: Spacing.s) {
                            amountField("מינימום", text: $minText)
                            Text("–")
                            amountField("מקסימום", text: $maxText)
                        }
                    }
                }
                .padding(Spacing.m)
            }
            .navigationTitle("סינון")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ניקוי") {
                        filter = TransactionFilter(searchText: filter.searchText)
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("הצגת \(preview.count) תוצאות") {
                    filter = applied
                    dismiss()
                }
                .buttonStyle(.primary)
                .padding(Spacing.m)
                .accessibilityIdentifier("filter.apply")
            }
        }
    }

    private var applied: TransactionFilter {
        var result = draft
        let calendar = Calendar.current
        result.dateRange = usesDates
            ? DateInterval(start: calendar.startOfDay(for: from),
                           end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to))!)
            : nil
        let minValue = AmountInput.decimal(from: minText)
        let maxValue = AmountInput.decimal(from: maxText)
        result.minAmount = minText.isEmpty ? nil : minValue
        result.maxAmount = maxText.isEmpty ? nil : maxValue
        return result
    }

    private var preview: [TransactionRow] {
        applied.apply(to: store.transactions) { store.category($0)?.name }
    }

    private func amountField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.control))
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
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
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? .white : .primary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(isOn ? Theme.brand : .clear, in: .rect(cornerRadius: 10))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("chip.\(title)")
            }
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
