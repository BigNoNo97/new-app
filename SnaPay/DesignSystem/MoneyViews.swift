import SwiftUI
import SnaPayCore

enum Money {
    /// "₪1,234.50" / "₪1,234" (no decimals for whole amounts): the currency sign before the
    /// number, wrapped in a left-to-right isolate so it reads the same inside Hebrew text.
    static func string(_ amount: Decimal, currency: String, alwaysShowCents: Bool = false, showsPlus: Bool = false) -> String {
        let hasCents = amount.rounded(scale: 0) != amount
        let number = abs(amount).formatted(
            .number.locale(Locale(identifier: "en_US")).precision(.fractionLength(hasCents || alwaysShowCents ? 2 : 0))
        )
        let sign = amount < 0 ? "-" : (showsPlus ? "+" : "")
        let symbol = CurrencyNames.symbol(for: currency)
        let separator = symbol.count > 1 && symbol.allSatisfy(\.isLetter) ? " " : ""
        return "\u{2066}\(sign)\(symbol)\(separator)\(number)\u{2069}"
    }

    /// Signed display for lists: income gets a "+", expenses show as positive amounts.
    static func listString(_ transaction: TransactionRow) -> String {
        string(transaction.amount, currency: transaction.currency, alwaysShowCents: true, showsPlus: transaction.kind == .income)
    }
}

/// An amount in the design's style: semibold, tabular digits, counting when it changes.
struct AmountText: View {
    let text: String
    var font: Font = Typography.heroAmount
    var color: Color = Theme.textPrimary

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
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

/// A category's emoji tile (a card-style placeholder when there is no category).
struct CategoryBadge: View {
    let category: CategoryItem?
    var size: CGFloat = 44

    var body: some View {
        if let category {
            EmojiTile(emoji: category.emoji, color: Color(hex: category.color), size: size)
        } else {
            Image(systemName: "creditcard")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: size, height: size)
                .background(Theme.fill, in: .rect(cornerRadius: size * 0.32))
        }
    }
}

/// A household member's initial in a colored circle (avatars are the one place for circles).
struct MemberAvatar: View {
    let id: UUID
    let name: String
    var size: CGFloat = 18

    private static let palette: [UInt32] = [0x5B8DEF, 0xE056B0, 0xF59E0B, 0x14B8A6, 0x8B5CF6]

    var body: some View {
        let index = id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % Self.palette.count
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(uiColor: UIColor(hex: Self.palette[index])), in: .circle)
            .accessibilityLabel(name)
    }
}

/// One transaction in a list: category tile, merchant, "category · time", the amount and
/// (under it) where it came from and who logged it.
struct TransactionRowView: View {
    let transaction: TransactionRow
    let category: CategoryItem?
    /// Shown in shared households.
    var member: HouseholdMember?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            CategoryBadge(category: category)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: 3) {
                AmountText(
                    text: transaction.isForeign
                        ? Money.string(transaction.originalAmount, currency: transaction.originalCurrency, alwaysShowCents: true)
                        : Money.listString(transaction),
                    font: .body.weight(.semibold),
                    color: transaction.kind == .income ? Theme.income : Theme.textPrimary
                )
                if transaction.isForeign {
                    Text("≈ \(Money.string(transaction.amount, currency: transaction.currency, alwaysShowCents: true))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                HStack(spacing: 5) {
                    if let member {
                        MemberAvatar(id: member.id, name: member.firstName)
                    }
                    Image(systemName: TransactionSourceStyle.symbol(for: transaction.source))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if let merchant = transaction.merchant, !merchant.isEmpty { return merchant }
        return category?.name ?? (transaction.kind == .income ? "הכנסה" : "הוצאה")
    }

    private var subtitle: String {
        let time = transaction.occurredAt.formatted(Date.FormatStyle(locale: Locale(identifier: "he_IL")).hour().minute())
        let first = transaction.kind == .income && category == nil ? "הכנסה" : category?.name
        let parts = [first, transaction.source == .recurring ? "חיוב קבוע" : time]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// Source icons from the design: Apple Pay, manual, receipt, recurring, import.
enum TransactionSourceStyle {
    static func symbol(for source: TransactionSource) -> String {
        switch source {
        case .applePay: "wave.3.right"
        case .manual: "pencil"
        case .receipt: "doc.text"
        case .recurring: "arrow.triangle.2.circlepath"
        case .imported, .openBanking: "square.and.arrow.down"
        }
    }

    static func name(for source: TransactionSource) -> String {
        switch source {
        case .applePay: "Apple Pay"
        case .manual: "ידני"
        case .receipt: "קבלה"
        case .recurring: "חיוב קבוע"
        case .imported: "ייבוא"
        case .openBanking: "בנקאות פתוחה"
        }
    }
}

/// Transactions grouped by day, newest first, inside glass cards.
struct DayGroupedList: View {
    let groups: [DayGroup]
    let store: TransactionStore
    var onSelect: (TransactionRow) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.sectionGap) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        Text(DayLabel.text(for: group.day))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(Money.string(abs(group.net), currency: store.mainCurrency, alwaysShowCents: true))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, Spacing.xs)

                    GlassCard(padding: Spacing.sm) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.transactions.enumerated()), id: \.element.id) { index, transaction in
                                Button {
                                    onSelect(transaction)
                                } label: {
                                    TransactionRowView(
                                        transaction: transaction,
                                        category: store.category(transaction.categoryID),
                                        member: store.isShared ? store.member(transaction.userID) : nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("transaction.\(transaction.merchant ?? transaction.id.uuidString)")
                                if index < group.transactions.count - 1 {
                                    Rectangle()
                                        .fill(Theme.separator)
                                        .frame(height: 1)
                                        .padding(.leading, 56)
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
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.brand)
                .frame(width: 96, height: 96)
                .glassSurface(radius: Radius.card)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(Theme.brand.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
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
            .foregroundStyle(store.syncProblem == .rejected ? Theme.warning : Theme.textSecondary)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, 10)
            .background(store.syncProblem == .rejected ? Theme.warningTint : Theme.fill, in: .rect(cornerRadius: Radius.chip))
            .accessibilityIdentifier("sync.banner")
        }
    }

    private var message: LocalizedStringKey {
        if store.syncProblem == .rejected { return "חלק מהשינויים לא נשמרו בשרת. נסו לרענן." }
        if store.pendingCount > 0 { return "\(store.pendingCount) שינויים ממתינים לחיבור" }
        return "אין חיבור. מוצג המידע האחרון שנשמר."
    }
}
