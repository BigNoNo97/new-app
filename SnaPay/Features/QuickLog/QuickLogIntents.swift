import AppIntents
import SwiftUI

// Quick-log from Apple Pay. The user sets up a Shortcuts "Transaction" automation once (see
// QuickLogSetupView) that runs `LogPaymentIntent` with the payment's amount, merchant and card.
// The intent saves the payment to the shared inbox and shows an interactive card: one tap on a
// category runs `ChooseCategoryIntent`, and the system redraws the card.
//
// The intent types are nonisolated (the target defaults to the main actor) and hand the work to
// `QuickLogService` on the main actor.

nonisolated struct LogPaymentIntent: AppIntent {
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
nonisolated struct QuickLogSnippetIntent: SnippetIntent {
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
nonisolated struct ChooseCategoryIntent: AppIntent {
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

/// The card itself. Plain rounded rectangles (no glass: the system draws the snippet's
/// background), right to left like the rest of the app.
nonisolated struct QuickLogCardView: View {
    let model: QuickLogCardModel

    @MainActor var body: some View {
        Group {
            switch model.state {
            case let .payment(id, merchant, amount, conversion, choices, chosen):
                payment(id: id, merchant: merchant, amount: amount, conversion: conversion, choices: choices, chosen: chosen)
            case let .message(title, detail):
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Spacing.m)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "he_IL"))
    }

    @MainActor private func payment(
        id: UUID, merchant: String, amount: String, conversion: String?,
        choices: [QuickLogCardModel.Choice], chosen: QuickLogCardModel.Choice?
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(merchant)
                        .font(.headline)
                        .lineLimit(1)
                    if let chosen {
                        Label("נשמר ב\(chosen.name)", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                    } else {
                        Text("באיזו קטגוריה?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(amount)
                        .font(.title3.weight(.semibold))
                    if let conversion {
                        Text(conversion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 3), spacing: Spacing.s) {
                ForEach(choices) { choice in
                    let isChosen = choice.id == chosen?.id
                    Button(intent: ChooseCategoryIntent(paymentID: id, categoryID: choice.id)) {
                        VStack(spacing: 4) {
                            Text(choice.emoji)
                                .font(.title2)
                            Text(choice.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color(hex: choice.color).opacity(isChosen ? 0.32 : 0.14), in: .rect(cornerRadius: Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.control)
                                .strokeBorder(isChosen ? Theme.brand : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isChosen ? .isSelected : [])
                }
            }

            if chosen == nil {
                Text("לא כאן? אפשר לבחור אחר כך במסך הבית של SnaPay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
