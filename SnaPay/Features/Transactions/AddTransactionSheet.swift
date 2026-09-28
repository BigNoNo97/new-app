import SwiftUI
import SnaPayCore

/// Add (or edit) an expense or income: amount keypad, currency with live conversion,
/// category, details, and optionally a recurring schedule.
struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: TransactionStore
    var editing: TransactionRow?

    @State private var draft: TransactionDraft
    @State private var amountText: String
    @State private var isRecurring = false
    @State private var frequency: RecurringRuleRow.Frequency = .monthly
    @State private var interval = 1
    @State private var hasEndDate = false
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(store: TransactionStore, editing: TransactionRow? = nil) {
        self.store = store
        self.editing = editing
        _draft = State(initialValue: editing.map(TransactionDraft.init(editing:)) ?? store.newDraft())
        _amountText = State(initialValue: editing.map { NSDecimalNumber(decimal: $0.originalAmount).stringValue } ?? "")
    }

    private var amount: Decimal { AmountInput.decimal(from: amountText) }

    private var conversion: Conversion? {
        var current = draft
        current.amount = amount
        return current.conversion(mainCurrency: store.mainCurrency, rates: store.rates, cardFeePercent: store.profile.cardFxFeePercent)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    GlassSegmentedControl(
                        selection: $draft.kind,
                        segments: [.init(value: .expense, title: "הוצאה"), .init(value: .income, title: "הכנסה")],
                        identifier: "add.kind"
                    )

                    amountSection
                    AmountKeypad(text: $amountText)
                    categorySection

                    VStack(spacing: Spacing.m) {
                        GlassTextField(title: draft.kind == .expense ? "בית עסק או תיאור" : "מקור ההכנסה",
                                       text: $draft.merchant, kind: .name, identifier: "add.merchant")
                        HStack {
                            Text("תאריך")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            DatePicker("", selection: $draft.occurredAt, in: ...Date.now.addingTimeInterval(60 * 60 * 24 * 365), displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .glassEffect(.regular, in: .rect(cornerRadius: Radius.control))
                        GlassTextField(title: "הערה", text: $draft.note, kind: .name, identifier: "add.note")
                    }

                    if editing == nil {
                        recurringSection
                    }

                    if let errorMessage {
                        ErrorBanner(message: LocalizedStringKey(errorMessage))
                    }
                }
                .padding(Spacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? "הוספה" : "עריכה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    LoadingLabel(title: "שמירה", isLoading: isSaving)
                }
                .buttonStyle(.primary)
                .disabled(isSaving || amount <= 0)
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.s)
                .accessibilityIdentifier("add.save")
            }
            .onChange(of: draft.kind) { _, kind in
                if !store.categories(for: kind).contains(where: { $0.id == draft.categoryID }) {
                    draft.categoryID = nil
                }
                if kind == .income { draft.currency = store.mainCurrency }
            }
        }
    }

    // MARK: Sections

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityIdentifier("add.amount")
                Menu {
                    Picker("מטבע", selection: $draft.currency) {
                        ForEach(SupportedCurrencies.all, id: \.self) { code in
                            Text(CurrencyNames.label(for: code)).tag(code)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(CurrencyNames.symbol(for: draft.currency))
                            .font(.title2.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.control))
                }
                .accessibilityIdentifier("add.currency")
                Spacer()
            }
            if let conversion {
                Text("≈ \(Money.string(conversion.totalAmount, currency: store.mainCurrency, alwaysShowCents: true))\(feeText(conversion))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("add.conversion")
            } else if draft.currency != store.mainCurrency {
                Text("שער ההמרה ייטען כשיהיה חיבור")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func feeText(_ conversion: Conversion) -> String {
        guard conversion.feeAmount > 0 else { return "" }
        let percent = NSDecimalNumber(decimal: store.profile.cardFxFeePercent).stringValue
        return " כולל \(percent)% עמלת המרה"
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("קטגוריה")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(store.categories(for: draft.kind)) { category in
                        let isSelected = draft.categoryID == category.id
                        Button {
                            draft.categoryID = isSelected ? nil : category.id
                        } label: {
                            VStack(spacing: 6) {
                                Text(category.emoji)
                                    .font(.title2)
                                    .frame(width: 52, height: 52)
                                    .background(Color(hex: category.color).opacity(0.18), in: .rect(cornerRadius: 16))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(isSelected ? Theme.brand : .clear, lineWidth: 2)
                                    }
                                Text(category.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 72)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("add.category.\(category.name)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var recurringSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Toggle(isOn: $isRecurring.animation()) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("חיוב קבוע")
                            .font(.body.weight(.medium))
                        Text("שכירות, מנויים, משכורת: יירשם לבד בכל פעם")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.rounded)
                .accessibilityIdentifier("add.recurring")

                if isRecurring {
                    GlassSegmentedControl(
                        selection: $frequency,
                        segments: [
                            .init(value: .weekly, title: "שבועי"),
                            .init(value: .monthly, title: "חודשי"),
                            .init(value: .yearly, title: "שנתי"),
                        ],
                        identifier: "add.frequency"
                    )
                    HStack {
                        Text("כל")
                        Menu {
                            Picker("", selection: $interval) {
                                ForEach(1...12, id: \.self) { Text("\($0)").tag($0) }
                            }
                        } label: {
                            Text("\(interval)")
                                .font(.body.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 36)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                        }
                        Text(unitName)
                        Spacer()
                    }
                    .font(.subheadline)
                    Toggle("תאריך סיום", isOn: $hasEndDate.animation())
                        .toggleStyle(.rounded)
                        .font(.subheadline)
                    if hasEndDate {
                        DatePicker("סיום", selection: $endDate, in: draft.occurredAt..., displayedComponents: .date)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var unitName: String {
        switch frequency {
        case .weekly, .everyDays: interval == 1 ? "שבוע" : "שבועות"
        case .monthly, .everyMonths: interval == 1 ? "חודש" : "חודשים"
        case .yearly: interval == 1 ? "שנה" : "שנים"
        }
    }

    // MARK: Save

    private func save() {
        draft.amount = amount
        errorMessage = nil
        guard draft.isValid else {
            errorMessage = "צריך להזין סכום"
            return
        }
        isSaving = true
        Task {
            do {
                if isRecurring && editing == nil {
                    try await store.createRecurring(
                        from: draft, frequency: frequency, interval: interval,
                        endsOn: hasEndDate ? endDate : nil
                    )
                } else {
                    try await store.save(draft, editing: editing)
                }
                dismiss()
            } catch StoreError.missingRate(let currency) {
                errorMessage = "אין כרגע שער המרה ל-\(currency). נסו שוב כשיש חיבור לאינטרנט."
            } catch StoreError.offline {
                errorMessage = "חיוב קבוע אפשר ליצור רק כשיש חיבור לאינטרנט."
            } catch {
                errorMessage = "לא הצלחנו לשמור. נסו שוב."
            }
            isSaving = false
        }
    }
}

/// Calculator-style keypad. Always left-to-right, like a phone keypad.
struct AmountKeypad: View {
    @Binding var text: String

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.s) {
            ForEach(keys, id: \.self) { key in
                Button {
                    text = AmountInput.apply(key: key, to: text)
                } label: {
                    Group {
                        if key == "⌫" {
                            Image(systemName: "delete.left")
                        } else {
                            Text(key)
                        }
                    }
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.control))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(key == "⌫" ? Text("מחיקה") : Text(key))
                .accessibilityIdentifier("key.\(key == "." ? "dot" : key == "⌫" ? "delete" : key)")
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}
