import SwiftUI
import SnaPayCore

/// Details of one transaction (design: `detail`). Only the person who logged it can edit or
/// delete it (the server enforces the same rule).
struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let store: TransactionStore
    let initial: TransactionRow

    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    init(store: TransactionStore, transaction: TransactionRow) {
        self.store = store
        self.initial = transaction
    }

    /// The latest version, so edits show up without reopening.
    private var transaction: TransactionRow {
        store.transactions.first { $0.id == initial.id } ?? initial
    }

    private var category: CategoryItem? { store.category(transaction.categoryID) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(transaction.kind == .income ? "פרטי הכנסה" : "פרטי הוצאה")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack {
                    IconButton(symbol: "chevron.backward", label: "סגירה") { dismiss() }
                    Spacer()
                    if store.canEdit(transaction) {
                        IconButton(symbol: "pencil", label: "עריכה") { isEditing = true }
                            .accessibilityIdentifier("detail.edit")
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.l)

            ScrollView {
                VStack(spacing: Spacing.m) {
                    header
                        .padding(.top, Spacing.m)
                        .padding(.bottom, Spacing.s)

                    if transaction.isForeign {
                        GlassCard(padding: Spacing.gutter) {
                            VStack(spacing: 0) {
                                DetailRow(label: "סכום מקורי") {
                                    Text(Money.string(transaction.originalAmount, currency: transaction.originalCurrency, alwaysShowCents: true))
                                }
                                separator
                                DetailRow(label: "שער המרה") {
                                    Text("\(Money.string(1, currency: transaction.originalCurrency)) = \(Money.string(transaction.exchangeRate.rounded(scale: 2), currency: transaction.currency, alwaysShowCents: true))")
                                }
                                if transaction.feeAmount > 0 {
                                    separator
                                    DetailRow(label: "עמלת המרה (\(feePercentText))") {
                                        Text(Money.string(transaction.feeAmount, currency: transaction.currency, alwaysShowCents: true))
                                    }
                                }
                                separator
                                DetailRow(label: "סה״כ בשקלים", isStrong: true) {
                                    Text(Money.string(transaction.amount, currency: transaction.currency, alwaysShowCents: true))
                                }
                            }
                        }
                        .accessibilityIdentifier("detail.conversion")
                    }

                    GlassCard(padding: Spacing.gutter) {
                        VStack(spacing: 0) {
                            DetailRow(label: "קטגוריה") {
                                HStack(spacing: Spacing.s) {
                                    if let category {
                                        EmojiTile(emoji: category.emoji, color: Color(hex: category.color), size: 28)
                                    }
                                    Text(category?.name ?? "ללא קטגוריה")
                                }
                            }
                            separator
                            DetailRow(label: "תאריך") {
                                Text(transaction.occurredAt.formatted(
                                    Date.FormatStyle(locale: Locale(identifier: "he_IL")).weekday(.abbreviated).day().month(.abbreviated).hour().minute()
                                ))
                            }
                            separator
                            DetailRow(label: "מקור") {
                                Label(TransactionSourceStyle.name(for: transaction.source), systemImage: TransactionSourceStyle.symbol(for: transaction.source))
                            }
                            if let member = store.member(transaction.userID) {
                                separator
                                DetailRow(label: "תועד על ידי") {
                                    HStack(spacing: Spacing.s) {
                                        MemberAvatar(id: member.id, name: member.firstName, size: 24)
                                        Text(member.id == store.userID ? "\(member.firstName) (אתה)" : member.firstName)
                                    }
                                }
                            }
                        }
                    }

                    if let note = transaction.note {
                        GlassCard(padding: Spacing.gutter) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("הערה")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(note)
                                    .font(.body)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }

                    if store.canEdit(transaction) {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label(transaction.kind == .income ? "מחיקת ההכנסה" : "מחיקת ההוצאה", systemImage: "trash")
                                .font(.headline)
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, minHeight: Metrics.buttonHeight)
                                .background(Theme.expenseTint, in: .rect(cornerRadius: Radius.control))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Spacing.s)
                        .accessibilityIdentifier("detail.delete")
                    } else {
                        Text("רק מי שתיעד את ההוצאה יכול לערוך או למחוק אותה.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.l)
            }
        }
        .background { AppBackground() }
        .sheet(isPresented: $isEditing) {
            AddTransactionSheet(store: store, editing: transaction)
        }
        .confirmationDialog("למחוק את ההוצאה?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("מחיקה", role: .destructive) {
                Task {
                    await store.delete(transaction)
                    dismiss()
                }
            }
            Button("ביטול", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.s) {
            CategoryBadge(category: category, size: 64)
            Text(transaction.merchant ?? category?.name ?? "")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            AmountText(
                text: transaction.isForeign
                    ? Money.string(transaction.originalAmount, currency: transaction.originalCurrency, alwaysShowCents: true)
                    : Money.listString(transaction),
                font: Typography.heroAmount,
                color: transaction.kind == .income ? Theme.income : Theme.textPrimary
            )
            .accessibilityIdentifier("detail.amount")
            if transaction.isForeign {
                Text("≈ \(Money.string(transaction.amount, currency: transaction.currency, alwaysShowCents: true))\(transaction.feeAmount > 0 ? " כולל עמלה" : "")")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var separator: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }

    /// The fee as a percent of the converted amount ("2.5%").
    private var feePercentText: String {
        let converted = transaction.amount - transaction.feeAmount
        guard converted > 0 else { return "" }
        let percent = (transaction.feeAmount / converted * 100).rounded(scale: 1)
        return "\(NSDecimalNumber(decimal: percent).stringValue)%"
    }
}

private struct DetailRow<Value: View>: View {
    let label: LocalizedStringKey
    var isStrong = false
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .foregroundStyle(isStrong ? Theme.textPrimary : Theme.textSecondary)
            Spacer(minLength: Spacing.m)
            value
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(isStrong ? .headline : .subheadline)
        .frame(minHeight: 50)
    }
}
