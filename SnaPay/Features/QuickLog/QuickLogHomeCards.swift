import SwiftUI
import SnaPayCore

/// Apple Pay payments the automation captured that still need a category (the user closed the
/// quick-log card, or it didn't show). One tap files each one.
struct PendingCapturesCard: View {
    let store: TransactionStore

    private static let visibleCount = 3

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    Label("ממתינים לסיווג", systemImage: "wave.3.right")
                        .font(.headline)
                    Spacer()
                    Text("\(store.pendingCaptures.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.pendingCaptures.prefix(Self.visibleCount)) { payment in
                    PendingCaptureRow(store: store, payment: payment)
                    if payment.id != store.pendingCaptures.prefix(Self.visibleCount).last?.id {
                        Divider()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending.card")
    }
}

private struct PendingCaptureRow: View {
    let store: TransactionStore
    let payment: CapturedPayment
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(payment.merchant.isEmpty ? "תשלום ב-Apple Pay" : payment.merchant)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(payment.capturedAt.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).weekday(.wide).hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.string(payment.amount, currency: payment.currency))
                    .font(.body.weight(.semibold))
                Menu {
                    Button("לא לתעד את התשלום", systemImage: "trash", role: .destructive) {
                        withAnimation { store.discardCapture(payment) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .accessibilityLabel("אפשרויות")
                .accessibilityIdentifier("pending.more")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    ForEach(store.quickLogSuggestions(for: payment)) { category in
                        Button {
                            isSaving = true
                            Task {
                                await store.categorizeCapture(payment, as: category.id)
                                isSaving = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(category.emoji)
                                Text(category.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 40)
                            .background(Color(hex: category.color).opacity(0.16), in: .rect(cornerRadius: Radius.control))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                        .accessibilityIdentifier("pending.category.\(category.name)")
                    }
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
                Image(systemName: "wave.3.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 40, height: 40)
                    .background(Theme.brand.opacity(0.14), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("תיעוד בקליק מ-Apple Pay")
                        .font(.headline)
                    Text("משלמים, ומיד קופצת חלונית לבחירת קטגוריה. ההגדרה לוקחת דקה.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("להגדרה", action: onOpen)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                        .accessibilityIdentifier("quicklog.setupCard.open")
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("סגירה")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quicklog.setupCard")
    }
}
