import Foundation
import SnaPayCore

/// What the quick-log card shows, computed on the main actor and handed to the snippet view.
nonisolated struct QuickLogCardModel: Sendable {
    nonisolated struct Choice: Sendable, Identifiable {
        let id: UUID
        let emoji: String
        let name: String
        let color: String
    }

    nonisolated enum State: Sendable {
        case payment(id: UUID, merchant: String, amount: String, conversion: String?, choices: [Choice], chosen: Choice?)
        case message(title: String, detail: String)
    }

    let state: State
}

/// The work behind the quick-log intents. Runs in the app's process, with or without a window.
enum QuickLogService {
    /// Keys the snippet intent receives instead of a payment id.
    enum Key {
        static let disabled = "disabled"
        static let signedOut = "signed-out"
        static let invalidAmount = "invalid-amount"
    }

    /// Where categorized payments are uploaded straight away. `nil` in UI tests; the app
    /// uploads whatever is left the next time it opens.
    static var repository: DataRepository? { AppConfig.isUITesting ? nil : SupabaseServices.shared }

    /// Saves the payment the automation reported. Returns the key for the card: the payment's
    /// id, or why nothing was captured.
    static func capture(amountText: String, merchant: String, card: String?) -> String {
        guard let context = QuickLogStorage.loadContext() else { return Key.signedOut }
        guard context.isEnabled else { return Key.disabled }
        guard let parsed = PaymentAmountParser.parse(amountText) else { return Key.invalidAmount }
        let payment = CapturedPayment(
            amount: parsed.amount,
            currency: parsed.currency ?? context.mainCurrency,
            merchant: merchant,
            card: card
        )
        let kept = QuickLogStorage.updateInbox { $0.add(payment) }
        NotificationCenter.default.post(name: .quickLogDidChange, object: nil)
        return kept.id.uuidString
    }

    /// Files the payment under the category the user tapped, then tries to upload it so a
    /// partner sees it right away. Offline, it stays in the inbox until the app syncs.
    static func choose(paymentID: UUID, categoryID: UUID) async {
        guard var context = QuickLogStorage.loadContext(),
              var payment = QuickLogStorage.loadInbox().payment(paymentID) else { return }
        let previous = payment.categoryID
        QuickLogStorage.updateInbox { $0.categorize(paymentID, as: categoryID) }
        payment.categoryID = categoryID
        if previous == nil {
            context.suggester.record(merchant: payment.merchant, categoryID: categoryID.uuidString)
            QuickLogStorage.saveContext(context)
        }
        NotificationCenter.default.post(name: .quickLogDidChange, object: nil)

        guard let repository else { return }
        if let row = try? context.makeRow(for: payment) {
            // Choosing again after an upload (to fix a wrong tap) updates the same row.
            if previous == nil {
                try? await repository.insertIgnoringDuplicates([row])
            } else {
                try? await repository.saveTransactions([row])
            }
        }
        try? await repository.recordMerchantCategory(householdID: context.householdID, merchant: payment.merchant, categoryID: categoryID)
    }

    static func card(for key: String) -> QuickLogCardModel {
        switch key {
        case Key.signedOut:
            return .init(state: .message(title: "צריך להתחבר ל-SnaPay", detail: "פותחים את SnaPay ומתחברים, והתשלומים הבאים יתועדו."))
        case Key.disabled:
            return .init(state: .message(title: "התיעוד בקליק כבוי", detail: "אפשר להפעיל אותו מחדש בפרופיל שב-SnaPay."))
        case Key.invalidAmount:
            return .init(state: .message(title: "לא הצלחנו לקרוא את הסכום", detail: "בדקו שבאוטומציה, בשדה הסכום, נבחר המשתנה \"סכום\" של העסקה."))
        default:
            break
        }
        guard let id = UUID(uuidString: key),
              let context = QuickLogStorage.loadContext(),
              let payment = QuickLogStorage.loadInbox().payment(id) else {
            return .init(state: .message(title: "התשלום כבר נשמר", detail: "אפשר לראות ולערוך אותו ב-SnaPay."))
        }
        let choices = context.suggestions(for: payment).map(choice)
        let chosen = payment.categoryID.flatMap { id in context.categories.first { $0.id == id } }.map(choice)
        let conversion = context.conversion(for: payment).map {
            "≈ " + Money.string($0.totalAmount, currency: context.mainCurrency, alwaysShowCents: true)
        }
        return .init(state: .payment(
            id: payment.id,
            merchant: payment.merchant.isEmpty ? "תשלום ב-Apple Pay" : payment.merchant,
            amount: Money.string(payment.amount, currency: payment.currency, alwaysShowCents: true),
            conversion: conversion,
            choices: choices,
            chosen: chosen
        ))
    }

    private static func choice(_ category: CategoryItem) -> QuickLogCardModel.Choice {
        .init(id: category.id, emoji: category.emoji, name: category.name, color: category.color)
    }
}
