import AppIntents

// Quick-log from Apple Pay. The user sets up a Shortcuts Wallet automation once (see
// QuickLogSetupView) that runs `LogPaymentIntent` with the transaction's amount, merchant and
// card. The intent saves the payment to the shared inbox and starts the quick-log Live Activity:
// the card expands out of the Dynamic Island (or shows on the Lock Screen), and one tap on a
// category runs `ChooseCategoryIntent` (Shared/QuickLogActivity.swift).
//
// As a `LiveActivityIntent` it runs in the app's process, which may start Live Activities from the
// background. `perform()` runs off the main actor; the work hops to the main actor.

struct LogPaymentIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "תיעוד תשלום"
    static var description: IntentDescription {
        IntentDescription("שומר תשלום ב-SnaPay ומציג חלון קטן לבחירת קטגוריה. מיועד לאוטומציית Wallet של קיצורים.")
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

    func perform() async throws -> some IntentResult {
        let key = await QuickLogService.capture(amountText: amount, merchant: merchant, card: card)
        await QuickLogLiveActivity.present(key: key)
        // The card shows right away; a slower guess from the on-device model updates it.
        if let id = UUID(uuidString: key), await QuickLogService.guessCategoryIfNeeded(paymentID: id) {
            await QuickLogLiveActivity.refresh(paymentID: id)
        }
        return .result()
    }
}
