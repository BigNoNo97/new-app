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
                Text("Apple Pay · \(payment.capturedAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "he_IL"))))")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: 6) {
                AmountText(text: Money.string(payment.amount, currency: payment.currency, alwaysShowCents: true), font: .body.weight(.bold))
                Button(action: onChoose) {
                    Text("בחירת קטגוריה")
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

/// Every category for a captured payment, the likeliest four first.
struct CaptureCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: TransactionStore
    let payment: CapturedPayment
    @State private var isSaving = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 4)

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

                section("מוצעות", categories: store.quickLogSuggestions(for: payment).prefix(4).map { $0 }, highlightsFirst: true)
                section("כל הקטגוריות", categories: store.categories(for: .expense), highlightsFirst: false)

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
        .designSheet()
        .presentationDetents([.large])
    }

    private func section(_ title: LocalizedStringKey, categories: [CategoryItem], highlightsFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: columns, spacing: Spacing.s) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    Button {
                        guard !isSaving else { return }
                        isSaving = true
                        Task {
                            await store.categorizeCapture(payment, as: category.id)
                            dismiss()
                        }
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
                            if highlightsFirst && index == 0 {
                                RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.brand, lineWidth: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
