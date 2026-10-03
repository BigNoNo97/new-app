import ActivityKit
import AppIntents
import Foundation

// Shared by the app and the widget extension: the quick-log Live Activity's data, and the
// intents behind its buttons. The widget draws the activity; as `LiveActivityIntent`s the
// buttons' intents run in the app's process, so their work is compiled into the app only
// (the widget target defines SNAPAY_WIDGET).

/// One payment waiting for a category: the card that expands out of the Dynamic Island (and
/// shows on the Lock Screen) after an Apple Pay payment.
nonisolated struct QuickLogActivityAttributes: ActivityAttributes {
    nonisolated struct Choice: Codable, Hashable, Sendable, Identifiable {
        let id: UUID
        let emoji: String
        let name: String
        /// "#2FB36D".
        let color: String
    }

    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var merchant: String
        /// In the payment's currency, "$23.00".
        var amount: String
        /// In the main currency, for the saved line.
        var mainAmount: String
        var card: String
        /// "≈ ₪86.40 כולל עמלה" for foreign payments.
        var conversion: String?
        /// Up to four suggestions, the likeliest first.
        var choices: [Choice]
        var chosen: Choice?
    }

    let paymentID: UUID
}

/// A category tapped on the card.
struct ChooseCategoryIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "בחירת קטגוריה"
    static let isDiscoverable = false

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
        #if !SNAPAY_WIDGET
        if let payment = UUID(uuidString: paymentID), let category = UUID(uuidString: categoryID) {
            await QuickLogService.choose(paymentID: payment, categoryID: category)
            await QuickLogLiveActivity.showSaved(paymentID: payment)
        }
        #endif
        return .result()
    }
}

/// "ביטול" on the saved line: the payment waits for a category again.
struct UndoCategoryIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "ביטול סיווג"
    static let isDiscoverable = false

    @Parameter(title: "תשלום")
    var paymentID: String

    init() {}

    init(paymentID: UUID) {
        self.paymentID = paymentID.uuidString
    }

    func perform() async throws -> some IntentResult {
        #if !SNAPAY_WIDGET
        if let payment = UUID(uuidString: paymentID) {
            await QuickLogService.undo(paymentID: payment)
            await QuickLogLiveActivity.start(paymentID: payment, alerting: false)
        }
        #endif
        return .result()
    }
}
