import SwiftUI
import SnaPayCore

enum Money {
    /// "₪1,234.50" / "₪1,234" (no decimals for whole amounts), Hebrew locale.
    static func string(_ amount: Decimal, currency: String, alwaysShowCents: Bool = false) -> String {
        let hasCents = amount.rounded(scale: 0) != amount
        let style = Decimal.FormatStyle.Currency(code: currency, locale: Locale(identifier: "he_IL"))
            .precision(.fractionLength(hasCents || alwaysShowCents ? 2 : 0))
        return amount.formatted(style)
    }

    /// Signed display for lists: income gets a "+", expenses show as positive amounts.
    static func listString(_ transaction: TransactionRow) -> String {
        let text = string(transaction.amount, currency: transaction.currency)
        return transaction.kind == .income ? "+" + text : text
    }
}

enum DayLabel {
    /// "היום", "אתמול", or "יום ג׳, 23 בספט׳".
    static func text(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "היום" }
        if calendar.isDateInYesterday(day) { return "אתמול" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        let style = Date.FormatStyle(locale: Locale(identifier: "he_IL"))
            .weekday(.abbreviated).day().month(.abbreviated)
        return sameYear ? day.formatted(style) : day.formatted(style.year())
    }
}

/// Emoji in a tinted rounded square.
struct CategoryBadge: View {
    let category: CategoryItem?
    var size: CGFloat = 44

    var body: some View {
        Text(category?.emoji ?? "💳")
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(
                (category.map { Color(hex: $0.color) } ?? Color.secondary).opacity(0.16),
                in: .rect(cornerRadius: size * 0.3)
            )
    }
}

/// One transaction in a list.
struct TransactionRowView: View {
    let transaction: TransactionRow
    let category: CategoryItem?
    /// Shown in shared households.
    var memberName: String?

    var body: some View {
        HStack(spacing: Spacing.m) {
            CategoryBadge(category: category)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let sourceSymbol {
                        Image(systemName: sourceSymbol)
                    }
                    Text(subtitle)
                        .lineLimit(1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.listString(transaction))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(transaction.kind == .income ? Theme.income : Color.primary)
                if transaction.isForeign {
                    Text(Money.string(transaction.originalAmount, currency: transaction.originalCurrency))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if let merchant = transaction.merchant, !merchant.isEmpty { return merchant }
        return category?.name ?? (transaction.kind == .income ? "הכנסה" : "הוצאה")
    }

    private var subtitle: String {
        let time = transaction.occurredAt.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).hour().minute())
        let parts = [category?.name, memberName, transaction.source == .recurring ? "חיוב קבוע" : time]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private var sourceSymbol: String? {
        switch transaction.source {
        case .applePay: "wave.3.right"
        case .recurring: "arrow.triangle.2.circlepath"
        case .receipt: "doc.text.viewfinder"
        case .imported, .openBanking: "building.columns"
        case .manual: nil
        }
    }
}

/// Transactions grouped by day, newest first, inside glass cards.
struct DayGroupedList: View {
    let groups: [DayGroup]
    let store: TransactionStore
    var onSelect: (TransactionRow) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        Text(DayLabel.text(for: group.day))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(Money.string(abs(group.net), currency: store.mainCurrency))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Spacing.xs)

                    GlassCard(padding: Spacing.s + 4) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.transactions.enumerated()), id: \.element.id) { index, transaction in
                                Button {
                                    onSelect(transaction)
                                } label: {
                                    TransactionRowView(
                                        transaction: transaction,
                                        category: store.category(transaction.categoryID),
                                        memberName: store.isShared ? store.memberName(transaction.userID) : nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("transaction.\(transaction.merchant ?? transaction.id.uuidString)")
                                if index < group.transactions.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Theme.brand)
                .frame(width: 80, height: 80)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}

/// A thin notice when changes are waiting for the connection, or the last sync failed.
struct SyncStatusBanner: View {
    let store: TransactionStore

    var body: some View {
        if store.pendingCount > 0 || store.syncProblem != nil {
            HStack(spacing: Spacing.s) {
                Image(systemName: store.syncProblem == .rejected ? "exclamationmark.triangle.fill" : "icloud.slash")
                Text(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.control))
            .accessibilityIdentifier("sync.banner")
        }
    }

    private var message: LocalizedStringKey {
        if store.syncProblem == .rejected { return "חלק מהשינויים לא נשמרו בשרת. נסו לרענן." }
        if store.pendingCount > 0 { return "\(store.pendingCount) שינויים ממתינים לחיבור" }
        return "אין חיבור. מוצג המידע האחרון שנשמר."
    }
}
