import ActivityKit
import SwiftUI
import WidgetKit

/// The quick-log card (design: `quicklog`, `quicklogfx`, `quicklogsaved`): a black card with the
/// card used, merchant and amount, four suggested categories (the likeliest highlighted) and
/// "עוד…"; after a tap, a "saved" line with undo. It expands out of the Dynamic Island and shows
/// on the Lock Screen. Always dark, right to left.
///
/// The widget can't see the app's `Theme`, so the few colors come from the design tokens here.
struct QuickLogActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: QuickLogActivityAttributes.self) { context in
            QuickLogCard(paymentID: context.attributes.paymentID, state: context.state)
                .padding(16)
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
                        VStack(alignment: .leading, spacing: 8) {
                            if let conversion = state.conversion {
                                Label(conversion, systemImage: "globe")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            CategoryRow(paymentID: paymentID, choices: state.choices)
                        }
                    }
                }
            } compactLeading: {
                BrandMark(size: 20)
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        CardBadge(card: state.card)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Apple Pay")
                            Text(state.card)
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        Spacer()
                        BrandMark(size: 28)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.merchant)
                                .font(.headline)
                                .lineLimit(1)
                            if let conversion = state.conversion {
                                Label(conversion, systemImage: "globe")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        Spacer(minLength: 8)
                        Text(state.amount)
                            .font(.system(size: 30, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .layoutPriority(1)
                    }
                    CategoryRow(paymentID: paymentID, choices: state.choices)
                }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// Four suggested categories (the likeliest highlighted) and "עוד…", which opens SnaPay where
/// the payment waits on Home with every category.
private struct CategoryRow: View {
    let paymentID: UUID
    let choices: [QuickLogActivityAttributes.Choice]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(choices.prefix(4).enumerated()), id: \.element.id) { index, choice in
                Button(intent: ChooseCategoryIntent(paymentID: paymentID, categoryID: choice.id)) {
                    tile(choice, isLikeliest: index == 0)
                }
                .buttonStyle(.plain)
            }
            Link(destination: URL(string: "snapay://quicklog")!) {
                VStack(spacing: 4) {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(height: 30)
                    Text("עוד…")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 66)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func tile(_ choice: QuickLogActivityAttributes.Choice, isLikeliest: Bool) -> some View {
        VStack(spacing: 4) {
            Text(choice.emoji)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(Color(hex: choice.color).opacity(0.28), in: .rect(cornerRadius: 9))
            Text(choice.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 66)
        .padding(.horizontal, 2)
        .background(isLikeliest ? QuickLogColors.brand.opacity(0.14) : .white.opacity(0.06), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
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
            Button(intent: UndoCategoryIntent(paymentID: paymentID)) {
                Text("ביטול")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
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
