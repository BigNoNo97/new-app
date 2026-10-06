import SwiftUI
import SnaPayCore

/// Apple Pay payments the automation captured that still need a category (the user closed the
/// quick-log card, or it didn't show). Highlighted at the top of Home (design: `home`).
struct PendingCapturesCard: View {
    let store: TransactionStore
    @State private var choosing: CapturedPayment?

    private static let visibleCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text(store.pendingCaptures.count == 1 ? "תשלום אחד מחכה לקטגוריה" : "\(store.pendingCaptures.count) תשלומים מחכים לקטגוריה")
            } icon: {
                Image(systemName: "sparkle")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.brandInk)

            ForEach(store.pendingCaptures.prefix(Self.visibleCount)) { payment in
                PendingCaptureRow(store: store, payment: payment) { choosing = payment }
                if payment.id != store.pendingCaptures.prefix(Self.visibleCount).last?.id {
                    Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, 56)
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.brandTint, Theme.glass], startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Theme.brand.opacity(0.55), lineWidth: 1.5)
        }
        .sheet(item: $choosing) { payment in
            CaptureCategorySheet(store: store, payment: payment)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending.card")
    }
}

private struct PendingCaptureRow: View {
    let store: TransactionStore
    let payment: CapturedPayment
    var onChoose: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.merchant.isEmpty ? "תשלום ב-Apple Pay" : payment.merchant)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let likely = store.likelyCategory(for: payment) {
                    Text("מוצע: \(likely.emoji) \(likely.name)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.brandInk)
                        .lineLimit(1)
                } else {
                    Text("Apple Pay · \(payment.capturedAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "he_IL"))))")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: 6) {
                AmountText(text: Money.string(payment.amount, currency: payment.currency, alwaysShowCents: true), font: .body.weight(.bold))
                Button(action: onChoose) {
                    Text(store.likelyCategory(for: payment) == nil ? "בחירת קטגוריה" : "אישור או שינוי")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.brandInk)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Theme.brandTint, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pending.choose")
            }
        }
        .contextMenu {
            Button("לא לתעד את התשלום", systemImage: "trash", role: .destructive) {
                withAnimation { store.discardCapture(payment) }
            }
        }
    }
}

/// Every category for a captured payment, the likeliest four first, with the category picked for
/// the user already selected, and a note. "שמירה" files it.
struct CaptureCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: TransactionStore
    let payment: CapturedPayment
    /// Opened from the note button on the quick-log card.
    let focusesNote: Bool
    @State private var selected: UUID?
    @State private var note: String
    @State private var isSaving = false
    @FocusState private var isNoteFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 4)

    init(store: TransactionStore, payment: CapturedPayment, focusesNote: Bool = false) {
        self.store = store
        self.payment = payment
        self.focusesNote = focusesNote
        _selected = State(initialValue: store.likelyCategory(for: payment)?.id)
        _note = State(initialValue: payment.note ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                SheetHeader(title: "בחירת קטגוריה") { dismiss() }
                    .padding(.top, Spacing.l)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payment.merchant.isEmpty ? "תשלום ב-Apple Pay" : payment.merchant)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(payment.capturedAt.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).weekday(.wide).hour().minute()))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    AmountText(text: Money.string(payment.amount, currency: payment.currency, alwaysShowCents: true), font: .title2.weight(.bold))
                }

                HStack(spacing: Spacing.sm) {
                    Label("הערה", systemImage: "doc.text")
                        .foregroundStyle(Theme.textPrimary)
                    TextField("הוספת הערה", text: $note)
                        .multilineTextAlignment(.trailing)
                        .focused($isNoteFocused)
                        .submitLabel(.done)
                        .accessibilityIdentifier("pending.note")
                }
                .font(.body)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 50)
                .glassSurface(radius: Radius.field)

                section("מוצעות", categories: store.quickLogSuggestions(for: payment).prefix(4).map { $0 })
                section("כל הקטגוריות", categories: store.categories(for: .expense))

                Button(role: .destructive) {
                    store.discardCapture(payment)
                    dismiss()
                } label: {
                    Label("לא לתעד את התשלום", systemImage: "trash")
                        .font(.headline)
                        .foregroundStyle(Theme.expense)
                        .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
                        .background(Theme.expenseTint, in: .rect(cornerRadius: Radius.control))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pending.discard")
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.l)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                save()
            } label: {
                Text(saveTitle)
            }
            .buttonStyle(.primary)
            .disabled(selected == nil || isSaving)
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.s)
            .accessibilityIdentifier("pending.save")
        }
        .designSheet()
        .presentationDetents([.large])
        .onAppear {
            if focusesNote { isNoteFocused = true }
        }
    }

    private var saveTitle: String {
        guard let selected, let category = store.categories(for: .expense).first(where: { $0.id == selected }) else {
            return "בחרו קטגוריה"
        }
        return "שמירה ב\(category.name)"
    }

    private func save() {
        guard let selected, !isSaving else { return }
        isSaving = true
        store.setCaptureNote(payment, note: note)
        Task {
            await store.categorizeCapture(payment, as: selected)
            dismiss()
        }
    }

    private func section(_ title: LocalizedStringKey, categories: [CategoryItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: columns, spacing: Spacing.s) {
                ForEach(categories) { category in
                    let isSelected = category.id == selected
                    Button {
                        selected = category.id
                    } label: {
                        VStack(spacing: 6) {
                            CategoryBadge(category: category, size: 40)
                            Text(category.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .glassSurface(radius: 18)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.brand, lineWidth: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("pending.category.\(category.name)")
                }
            }
        }
    }
}

/// Invites the user to set up quick-log until the first payment arrives.
struct QuickLogSetupCard: View {
    var onOpen: () -> Void
    var onClose: () -> Void

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: Spacing.m) {
                FeatureIcon(symbol: "wave.3.right", size: 40)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("תיעוד בקליק מ-Apple Pay")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("משלמים, ומיד קופצת חלונית לבחירת קטגוריה. ההגדרה לוקחת דקה.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Button("להגדרה", action: onOpen)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.brandInk)
                        .accessibilityIdentifier("quicklog.setupCard.open")
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("הסתרת הכרטיס")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quicklog.setupCard")
    }
}
