import SwiftUI
import SnaPayCore

/// Add (or edit) an expense or income (design: `add`, `adddetails`). The first page is the
/// amount, category and merchant with a keypad; "פרטים נוספים" opens the second page with the
/// date, a note, the receipt and the recurring schedule.
struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: TransactionStore
    var editing: TransactionRow?

    private enum Page { case amount, details }

    @State private var page: Page = .amount
    @State private var draft: TransactionDraft
    @State private var amountText: String
    @State private var isRecurring = false
    @State private var frequency: RecurringRuleRow.Frequency = .monthly
    @State private var interval = 1
    @State private var hasEndDate = false
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingReceiptNotice = false

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
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.sm)

            Group {
                switch page {
                case .amount: amountPage
                case .details: detailsPage
                }
            }
            .transition(.opacity)

            VStack(spacing: Spacing.s) {
                if let errorMessage {
                    ErrorBanner(message: LocalizedStringKey(errorMessage))
                }
                Button(action: save) {
                    LoadingLabel(title: "שמירה", isLoading: isSaving)
                }
                .buttonStyle(.primary)
                .disabled(isSaving || amount <= 0)
                .accessibilityIdentifier("add.save")
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.s)
        }
        .animation(.easeInOut(duration: 0.2), value: page)
        .designSheet()
        .onChange(of: draft.kind) { _, kind in
            if !store.categories(for: kind).contains(where: { $0.id == draft.categoryID }) {
                draft.categoryID = nil
            }
            if kind == .income { draft.currency = store.mainCurrency }
        }
        .alert("צילום קבלה", isPresented: $isShowingReceiptNotice) {
            Button("הבנתי", role: .cancel) {}
        } message: {
            Text("צילום קבלות וזיהוי הסכום יגיעו בעדכון הקרוב.")
        }
    }

    /// Kind switch with a close (or back) button.
    private var header: some View {
        HStack(spacing: Spacing.sm) {
            GlassSegmentedControl(
                selection: $draft.kind,
                segments: [.init(value: .expense, title: "הוצאה"), .init(value: .income, title: "הכנסה")],
                identifier: "add.kind"
            )
            if page == .details {
                IconButton(symbol: "chevron.backward", label: "חזרה") { page = .amount }
            } else {
                IconButton(symbol: "xmark", label: "ביטול") { dismiss() }
                    .accessibilityIdentifier("add.cancel")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: Amount page

    private var amountPage: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                if draft.kind == .expense, let trip = store.activeTrip, draft.currency == trip.tripCurrency {
                    Text("\(trip.emoji) \(trip.name)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(hex: trip.color))
                        .padding(.horizontal, Spacing.sm)
                        .frame(height: 32)
                        .background(Color(hex: trip.color).opacity(0.16), in: .rect(cornerRadius: 10))
                }

                amountSection
                categorySection

                HStack(spacing: Spacing.s) {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Theme.textTertiary)
                        TextField(draft.kind == .expense ? "בית עסק / תיאור" : "מקור ההכנסה", text: $draft.merchant)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("add.merchant")
                    }
                    .fieldSurface()
                    Button {
                        isShowingReceiptNotice = true
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.brandInk)
                            .frame(width: 52, height: Metrics.fieldHeight)
                            .background(Theme.field, in: .rect(cornerRadius: Radius.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("צילום קבלה")
                }

                AmountKeypad(text: $amountText)

                Button {
                    page = .details
                } label: {
                    Label(detailsSummary, systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.text)
                .accessibilityIdentifier("add.details")
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.s)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// "פרטים נוספים", or what's already set there.
    private var detailsSummary: String {
        var parts: [String] = []
        if !Calendar.current.isDateInToday(draft.occurredAt) {
            parts.append(draft.occurredAt.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.abbreviated)))
        }
        if isRecurring { parts.append("חיוב קבוע") }
        if !draft.note.isEmpty { parts.append("הערה") }
        return parts.isEmpty ? "פרטים נוספים" : "פרטים: " + parts.joined(separator: " · ")
    }

    private var amountSection: some View {
        VStack(spacing: Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                AmountText(text: amountText.isEmpty ? "0" : AmountInput.grouped(amountText), font: .system(size: 64, weight: .bold))
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityIdentifier("add.amount")
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.brand)
                    .frame(width: 3, height: 52)
                    .accessibilityHidden(true)
                Menu {
                    Picker("מטבע", selection: $draft.currency) {
                        ForEach(SupportedCurrencies.all, id: \.self) { code in
                            Text(CurrencyNames.label(for: code)).tag(code)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(CurrencyNames.symbol(for: draft.currency))
                            .font(.title3.weight(.bold))
                        Text(draft.currency)
                            .font(.subheadline.weight(.bold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Spacing.sm)
                    .frame(height: 44)
                    .glassSurface(radius: Radius.field, interactive: true)
                }
                .accessibilityIdentifier("add.currency")
            }
            .frame(maxWidth: .infinity)
            if let conversion {
                Text("≈ \(Money.string(conversion.totalAmount, currency: store.mainCurrency, alwaysShowCents: true))\(feeText(conversion))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("add.conversion")
            } else if draft.currency != store.mainCurrency {
                Text("שער ההמרה ייטען כשיהיה חיבור")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func feeText(_ conversion: Conversion) -> String {
        guard conversion.feeAmount > 0 else { return "" }
        let percent = NSDecimalNumber(decimal: store.profile.cardFxFeePercent).stringValue
        return " כולל \(percent)% עמלת המרה"
    }

    private var categorySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(store.categories(for: draft.kind)) { category in
                    let isSelected = draft.categoryID == category.id
                    Button {
                        draft.categoryID = isSelected ? nil : category.id
                    } label: {
                        VStack(spacing: 6) {
                            EmojiTile(emoji: category.emoji, color: Color(hex: category.color), size: 48)
                                .padding(3)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(isSelected ? Theme.brand : .clear, lineWidth: 2.5)
                                }
                            Text(category.name)
                                .font(.caption)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .frame(width: 66)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("add.category.\(category.name)")
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, Spacing.gutter)
        }
        .padding(.horizontal, -Spacing.gutter)
    }

    // MARK: Details page

    private var detailsPage: some View {
        ScrollView {
            VStack(spacing: Spacing.cardGap) {
                GlassCard(padding: Spacing.gutter) {
                    HStack(spacing: Spacing.sm) {
                        CategoryBadge(category: store.category(draft.categoryID), size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.category(draft.categoryID)?.name ?? "ללא קטגוריה")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                            Text(draft.merchant.isEmpty ? (draft.kind == .expense ? "הוצאה" : "הכנסה") : draft.merchant)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                        }
                        Spacer()
                        AmountText(text: Money.string(amount, currency: draft.currency, alwaysShowCents: true), font: .title2.weight(.bold))
                    }
                }

                GlassCard(padding: Spacing.gutter) {
                    VStack(spacing: 0) {
                        HStack {
                            Label("תאריך", systemImage: "calendar")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            DatePicker("", selection: $draft.occurredAt, in: ...Date.now.addingTimeInterval(60 * 60 * 24 * 365),
                                       displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .tint(Theme.brand)
                        }
                        .frame(minHeight: 50)
                        Rectangle().fill(Theme.separator).frame(height: 1)
                        HStack(spacing: Spacing.sm) {
                            Label("הערה", systemImage: "doc.text")
                                .foregroundStyle(Theme.textPrimary)
                            TextField("הוספת הערה", text: $draft.note)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("add.note")
                        }
                        .frame(minHeight: 50)
                    }
                    .font(.body)
                }

                Button {
                    isShowingReceiptNotice = true
                } label: {
                    Label("צלם קבלה", systemImage: "camera")
                }
                .buttonStyle(.glassSecondary)

                if editing == nil {
                    recurringSection
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.m)
        }
    }

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Toggle(isOn: $isRecurring.animation()) {
                Label {
                    Text("חיוב קבוע")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Theme.brandInk)
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
                HStack(spacing: Spacing.s) {
                    Text("כל")
                    Menu {
                        Picker("", selection: $interval) {
                            ForEach(1...12, id: \.self) { Text("\($0)").tag($0) }
                        }
                    } label: {
                        Text("\(interval)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(minWidth: 44, minHeight: 36)
                            .background(Theme.field, in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                    Text(unitName)
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

                HStack(spacing: Spacing.s) {
                    dateBox(title: "התחלה", value: draft.occurredAt.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.abbreviated).year()))
                    Button {
                        withAnimation { hasEndDate.toggle() }
                    } label: {
                        dateBox(title: "סיום (לא חובה)", value: hasEndDate
                                ? endDate.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.abbreviated).year())
                                : "ללא תאריך סיום")
                    }
                    .buttonStyle(.plain)
                }
                if hasEndDate {
                    DatePicker("תאריך סיום", selection: $endDate, in: draft.occurredAt..., displayedComponents: .date)
                        .font(.subheadline)
                        .tint(Theme.brand)
                }
                if let next = nextCharge {
                    Label("החיוב הבא: \(next.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.abbreviated).year()))",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(Spacing.gutter)
        .glassSurface()
        .overlay {
            if isRecurring {
                RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Theme.brand.opacity(0.45), lineWidth: 1.5)
            }
        }
    }

    private func dateBox(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Theme.field, in: .rect(cornerRadius: Radius.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    /// The charge after the first one.
    private var nextCharge: Date? {
        let calendar = Calendar.current
        let step = max(interval, 1)
        switch frequency {
        case .weekly, .everyDays: return calendar.date(byAdding: .weekOfYear, value: step, to: draft.occurredAt)
        case .monthly, .everyMonths: return calendar.date(byAdding: .month, value: step, to: draft.occurredAt)
        case .yearly: return calendar.date(byAdding: .year, value: step, to: draft.occurredAt)
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

/// Calculator-style keypad (design: keys 52pt, radius 14; "." and delete without a key face).
/// Always left to right, like a phone keypad.
struct AmountKeypad: View {
    @Binding var text: String

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.sm) {
            ForEach(keys, id: \.self) { key in
                let isPlain = key == "." || key == "⌫"
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
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(isPlain ? Color.clear : Theme.field, in: .rect(cornerRadius: Radius.field))
                    .overlay {
                        if !isPlain {
                            RoundedRectangle(cornerRadius: Radius.field).strokeBorder(Theme.stroke, lineWidth: 1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(key == "⌫" ? Text("מחיקה") : Text(key))
                .accessibilityIdentifier("key.\(key == "." ? "dot" : key == "⌫" ? "delete" : key)")
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}
