import SwiftUI
import SnaPayCore

/// Details of one transaction. Only the person who logged it can edit or delete it
/// (the server enforces the same rule).
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
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    VStack(spacing: Spacing.s) {
                        CategoryBadge(category: category, size: 72)
                        Text(transaction.merchant ?? category?.name ?? "")
                            .font(.title2.weight(.semibold))
                        Text(Money.listString(transaction))
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .foregroundStyle(transaction.kind == .income ? Theme.income : Color.primary)
                            .accessibilityIdentifier("detail.amount")
                    }
                    .padding(.top, Spacing.m)

                    GlassCard {
                        VStack(spacing: 0) {
                            DetailRow(label: "קטגוריה", value: category.map { "\($0.emoji) \($0.name)" } ?? "ללא קטגוריה")
                            Divider()
                            DetailRow(label: "תאריך", value: transaction.occurredAt.formatted(
                                Date.FormatStyle(locale: Locale(identifier: "he_IL")).day().month(.wide).year().hour().minute()
                            ))
                            if store.isShared, let name = store.memberName(transaction.userID) {
                                Divider()
                                DetailRow(label: "הוזן על ידי", value: name)
                            }
                            Divider()
                            DetailRow(label: "מקור", value: CSVExporter.sourceName(transaction.source))
                            if let note = transaction.note {
                                Divider()
                                DetailRow(label: "הערה", value: note)
                            }
                        }
                    }

                    if transaction.isForeign {
                        GlassCard {
                            VStack(spacing: 0) {
                                DetailRow(label: "סכום ששולם", value: Money.string(transaction.originalAmount, currency: transaction.originalCurrency, alwaysShowCents: true))
                                Divider()
                                DetailRow(label: "שער", value: "1 \(transaction.originalCurrency) = \(NSDecimalNumber(decimal: transaction.exchangeRate.rounded(scale: 4)).stringValue) \(transaction.currency)")
                                if transaction.feeAmount > 0 {
                                    Divider()
                                    DetailRow(label: "עמלת המרה", value: Money.string(transaction.feeAmount, currency: transaction.currency, alwaysShowCents: true))
                                }
                                Divider()
                                DetailRow(label: "סה\"כ בחיוב", value: Money.string(transaction.amount, currency: transaction.currency, alwaysShowCents: true))
                            }
                        }
                        .accessibilityIdentifier("detail.conversion")
                    }

                    if store.canEdit(transaction) {
                        VStack(spacing: Spacing.s) {
                            Button("עריכה") { isEditing = true }
                                .buttonStyle(.glassSecondary)
                                .accessibilityIdentifier("detail.edit")
                            Button("מחיקה", role: .destructive) { isConfirmingDelete = true }
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.expense)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("detail.delete")
                        }
                    } else {
                        Text("רק מי שהזין את ההוצאה יכול לערוך או למחוק אותה.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Spacing.m)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגירה") { dismiss() }
                }
            }
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
    }
}

private struct DetailRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.m)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }
}
