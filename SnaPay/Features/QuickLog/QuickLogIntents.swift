import AppIntents
import SwiftUI

// Quick-log from Apple Pay. The user sets up a Shortcuts "Transaction" automation once (see
// QuickLogSetupView) that runs `LogPaymentIntent` with the payment's amount, merchant and card.
// The intent saves the payment to the shared inbox and shows an interactive card: one tap on a
// category runs `ChooseCategoryIntent`, and the system redraws the card.
//
// `perform()` runs off the main actor (the AppIntent requirement); the work hops to
// `QuickLogService` on the main actor.

struct LogPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "תיעוד תשלום"
    static var description: IntentDescription {
        IntentDescription("שומר תשלום ב-SnaPay ומציג חלונית קטנה לבחירת קטגוריה. מיועד לאוטומציית \"עסקה\" של קיצורים.")
    }
    static let openAppWhenRun = false

    @Parameter(title: "סכום", description: "הסכום ששולם, למשל ₪18.50")
    var amount: String

    @Parameter(title: "בית עסק")
    var merchant: String

    @Parameter(title: "כרטיס")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("תיעוד \(\.$amount) ב-\(\.$merchant)") {
            \.$card
        }
    }

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        let key = await QuickLogService.capture(amountText: amount, merchant: merchant, card: card)
        return .result(snippetIntent: QuickLogSnippetIntent(key: key))
    }
}

/// Draws the quick-log card for a captured payment (or a message when nothing was captured).
struct QuickLogSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "חלונית תיעוד"
    static let isDiscoverable = false

    /// A payment id, or one of `QuickLogService.Key`.
    @Parameter(title: "תשלום")
    var key: String

    init() {}

    init(key: String) {
        self.key = key
    }

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let model = await QuickLogService.card(for: key)
        return .result(view: QuickLogCardView(model: model))
    }
}

/// A category tapped on the quick-log card.
struct ChooseCategoryIntent: AppIntent {
    static let title: LocalizedStringResource = "בחירת קטגוריה"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "תשלום")
    var paymentID: String

    @Parameter(title: "קטגוריה")
    var categoryID: String

    init() {}

    init(paymentID: UUID, categoryID: UUID) {
        self.paymentID = paymentID.uuidString
        self.categoryID = categoryID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let payment = UUID(uuidString: paymentID), let category = UUID(uuidString: categoryID) {
            await QuickLogService.choose(paymentID: payment, categoryID: category)
        }
        return .result()
    }
}

/// "ביטול" on the saved card.
struct UndoCategoryIntent: AppIntent {
    static let title: LocalizedStringResource = "ביטול סיווג"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "תשלום")
    var paymentID: String

    init() {}

    init(paymentID: UUID) {
        self.paymentID = paymentID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let payment = UUID(uuidString: paymentID) {
            await QuickLogService.undo(paymentID: payment)
        }
        return .result()
    }
}

/// "עוד…" on the card: opens SnaPay, where the payment waits on Home with every category.
struct OpenSnaPayIntent: AppIntent {
    static let title: LocalizedStringResource = "פתיחת SnaPay"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// The card itself (design: `quicklog`, `quicklogfx`, `quicklogsaved`): a black card with the
/// card used, merchant and amount, four suggested categories (the likeliest highlighted) and
/// "עוד…"; after a tap it collapses to a "saved" line with undo. Always dark, right to left.
nonisolated struct QuickLogCardView: View {
    let model: QuickLogCardModel

    @MainActor var body: some View {
        Group {
            switch model.state {
            case let .payment(payment):
                if let chosen = payment.chosen {
                    saved(payment, chosen: chosen)
                } else {
                    choosing(payment)
                }
            case let .message(title, detail):
                HStack(alignment: .top, spacing: Spacing.sm) {
                    BrandTile(size: 36)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.white)
                .padding(Spacing.m)
            }
        }
        .background(.black, in: .rect(cornerRadius: 38))
        .environment(\.colorScheme, .dark)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "he_IL"))
    }

    @MainActor private func choosing(_ payment: QuickLogCardModel.Payment) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Text(String(payment.card.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: UIColor(hex: 0x5B8DEF)))
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: UIColor(hex: 0x5B8DEF)).opacity(0.22), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Apple Pay")
                    Text(payment.card)
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                Spacer()
                BrandTile(size: 32)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(payment.merchant)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    if let conversion = payment.conversion {
                        Label(conversion, systemImage: "globe")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer(minLength: Spacing.s)
                AmountText(text: payment.amount, font: .system(size: 36, weight: .bold), color: .white)
                    .layoutPriority(1)
            }

            Text("לאיזו קטגוריה?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: Spacing.s) {
                ForEach(Array(payment.choices.enumerated()), id: \.element.id) { index, choice in
                    Button(intent: ChooseCategoryIntent(paymentID: payment.id, categoryID: choice.id)) {
                        tile(emoji: choice.emoji, name: choice.name, color: Color(hex: choice.color), isLikeliest: index == 0)
                    }
                    .buttonStyle(.plain)
                }
                Button(intent: OpenSnaPayIntent()) {
                    VStack(spacing: 6) {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(height: 40)
                        Text("עוד…")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(Spacing.m)
    }

    @MainActor private func tile(emoji: String, name: String, color: Color, isLikeliest: Bool) -> some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.28), in: .rect(cornerRadius: 12))
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(.horizontal, 2)
        .background(isLikeliest ? Theme.brand.opacity(0.14) : .white.opacity(0.06), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isLikeliest ? Theme.brand : .white.opacity(0.1), lineWidth: isLikeliest ? 2 : 1)
        }
    }

    @MainActor private func saved(_ payment: QuickLogCardModel.Payment, chosen: QuickLogCardModel.Choice) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(uiColor: UIColor(hex: 0x04210F)))
                .frame(width: 36, height: 36)
                .background(Theme.brand, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text("נשמר ב\(chosen.name)")
                    .font(.subheadline.weight(.bold))
                Text("\(payment.merchant) · \(payment.mainAmount)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            Spacer(minLength: Spacing.s)
            Button(intent: UndoCategoryIntent(paymentID: payment.id)) {
                Text("ביטול")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.m)
                    .frame(height: 36)
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 10)
    }
}
