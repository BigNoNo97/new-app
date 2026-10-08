import ActivityKit
import SwiftUI
import WidgetKit

/// The quick-log card (design: `quicklog`, `quicklogfx`, `quicklogsaved`): a black card with the
/// card used, merchant and amount, the category picked for the user with "אישור" (when there is
/// one), other categories and "עוד…"; after a tap, a "saved" line with undo and a note link. It
/// expands out of the Dynamic Island and shows on the Lock Screen (both are limited to about 160
/// points of height). Always dark, right to left.
///
/// The widget can't see the app's `Theme`, so the few colors come from the design tokens here.
struct QuickLogActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: QuickLogActivityAttributes.self) { context in
            QuickLogCard(paymentID: context.attributes.paymentID, state: context.state)
                .padding(14)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let paymentID = context.attributes.paymentID
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if state.chosen == nil {
                        CardBadge(card: state.card)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.chosen == nil {
                        Text(state.amount)
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if state.chosen == nil {
                        Text(state.merchant)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let chosen = state.chosen {
                        SavedLine(paymentID: paymentID, state: state, chosen: chosen)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            if let conversion = state.conversion {
                                Label(conversion, systemImage: "globe")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            ChoosingRows(paymentID: paymentID, state: state)
                        }
                    }
                }
            } compactLeading: {
                // The category picked for the user, so the pill says what "אישור" would save.
                if state.chosen == nil, let suggested = state.suggested {
                    Text(suggested.emoji)
                        .font(.system(size: 16))
                } else {
                    BrandMark(size: 20)
                }
            } compactTrailing: {
                Text(state.chosen == nil ? state.amount : "✓")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(QuickLogColors.brand)
            } minimal: {
                BrandMark(size: 20)
            }
            .keylineTint(QuickLogColors.brand)
        }
    }
}

private enum QuickLogColors {
    /// `color.brand.dark` (the card is always dark).
    static let brand = Color(hex: "#3DDC84")
    static let cardBlue = Color(hex: "#5B8DEF")
    static let savedInk = Color(hex: "#04210F")
}

/// The Lock Screen card.
private struct QuickLogCard: View {
    let paymentID: UUID
    let state: QuickLogActivityAttributes.ContentState

    var body: some View {
        Group {
            if let chosen = state.chosen {
                SavedLine(paymentID: paymentID, state: state, chosen: chosen)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        CardBadge(card: state.card)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(state.merchant)
                                .font(.headline)
                            Text(state.conversion ?? "\(state.card) · Apple Pay")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(state.amount)
                            .font(.system(size: 26, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .layoutPriority(1)
                    }
                    ChoosingRows(paymentID: paymentID, state: state)
                }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// Opens SnaPay on this payment: every category, and the note field when `note` is set.
private func paymentURL(_ paymentID: UUID, note: Bool = false) -> URL {
    URL(string: "snapay://quicklog/\(paymentID.uuidString)\(note ? "?note=1" : "")")!
}

/// While a payment waits: the category picked for the user with "אישור" and three others, or,
/// without a pick, four categories (the likeliest highlighted). "עוד…" opens SnaPay on the payment.
private struct ChoosingRows: View {
    let paymentID: UUID
    let state: QuickLogActivityAttributes.ContentState

    var body: some View {
        if let suggested = state.suggested {
            VStack(spacing: 6) {
                SuggestedRow(paymentID: paymentID, suggested: suggested, hasNote: state.hasNote)
                CategoryRow(paymentID: paymentID, choices: Array(state.choices.filter { $0.id != suggested.id }.prefix(3)),
                            highlightsFirst: false, isCompact: true)
            }
        } else {
            CategoryRow(paymentID: paymentID, choices: Array(state.choices.prefix(4)), highlightsFirst: true, isCompact: false)
        }
    }
}

/// "🍔 אוכל ומסעדות · נבחרה בשבילך" with a note link and "אישור".
private struct SuggestedRow: View {
    let paymentID: UUID
    let suggested: QuickLogActivityAttributes.Choice
    let hasNote: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(suggested.emoji)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(Color(hex: suggested.color).opacity(0.28), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 0) {
                Text(suggested.name)
                    .font(.subheadline.weight(.bold))
                Text("נבחרה בשבילך")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(QuickLogColors.brand)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            NoteLink(paymentID: paymentID, hasNote: hasNote)
            Button(intent: ChooseCategoryIntent(paymentID: paymentID, categoryID: suggested.id)) {
                Text("אישור")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(QuickLogColors.savedInk)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(QuickLogColors.brand, in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// A pencil that opens SnaPay on the payment with the note field ready (a Live Activity can't
/// take typing).
private struct NoteLink: View {
    let paymentID: UUID
    let hasNote: Bool

    var body: some View {
        Link(destination: paymentURL(paymentID, note: true)) {
            Image(systemName: hasNote ? "note.text" : "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.12), in: .rect(cornerRadius: 10))
        }
        .accessibilityLabel(hasNote ? "עריכת הערה" : "הוספת הערה")
    }
}

/// Category tiles and "עוד…". Compact under the suggested row, to fit the card's height.
private struct CategoryRow: View {
    let paymentID: UUID
    let choices: [QuickLogActivityAttributes.Choice]
    let highlightsFirst: Bool
    let isCompact: Bool

    private var tileHeight: CGFloat { isCompact ? 42 : 58 }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                Button(intent: ChooseCategoryIntent(paymentID: paymentID, categoryID: choice.id)) {
                    tile(choice, isLikeliest: highlightsFirst && index == 0)
                }
                .buttonStyle(.plain)
            }
            Link(destination: paymentURL(paymentID)) {
                VStack(spacing: isCompact ? 1 : 4) {
                    Image(systemName: "ellipsis")
                        .font(isCompact ? .subheadline : .headline)
                        .frame(height: isCompact ? 20 : 28)
                    Text("עוד…")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: tileHeight)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func tile(_ choice: QuickLogActivityAttributes.Choice, isLikeliest: Bool) -> some View {
        VStack(spacing: isCompact ? 1 : 4) {
            Text(choice.emoji)
                .font(isCompact ? .body : .title3)
                .frame(width: isCompact ? 22 : 30, height: isCompact ? 20 : 30)
                .background(isCompact ? .clear : Color(hex: choice.color).opacity(0.28), in: .rect(cornerRadius: 8))
            Text(choice.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: tileHeight)
        .padding(.horizontal, 2)
        .background(isLikeliest ? QuickLogColors.brand.opacity(0.14) : .white.opacity(0.06), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isLikeliest ? QuickLogColors.brand : .white.opacity(0.1), lineWidth: isLikeliest ? 2 : 1)
        }
    }
}

/// "נשמר באוכל ומסעדות" with undo, after a category was tapped.
private struct SavedLine: View {
    let paymentID: UUID
    let state: QuickLogActivityAttributes.ContentState
    let chosen: QuickLogActivityAttributes.Choice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(QuickLogColors.savedInk)
                .frame(width: 32, height: 32)
                .background(QuickLogColors.brand, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text("נשמר ב\(chosen.name)")
                    .font(.subheadline.weight(.bold))
                Text("\(state.merchant) · \(state.mainAmount)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            NoteLink(paymentID: paymentID, hasNote: state.hasNote)
            Button(intent: UndoCategoryIntent(paymentID: paymentID)) {
                Text("ביטול")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// The card's first letter on a blue tile, as on the design's card.
private struct CardBadge: View {
    let card: String

    var body: some View {
        Text(String(card.prefix(1)).uppercased())
            .font(.subheadline.weight(.bold))
            .foregroundStyle(QuickLogColors.cardBlue)
            .frame(width: 30, height: 30)
            .background(QuickLogColors.cardBlue.opacity(0.22), in: .rect(cornerRadius: 9))
    }
}

private struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        Image("BrandSymbol")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private extension Color {
    /// From "#RRGGBB" (category colors and design tokens).
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(digits, radix: 16) ?? 0x888888
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
